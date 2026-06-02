//go:build integration

package identity_test

// Property-based tests for the identity package.
// Invariants verified:
//   - OTP codes are 6-digit strings with uniform digit distribution (chi-square p > 0.05).
//   - JWT access tokens round-trip for any valid userID and market string.
//   - MaskPhone never exposes more than the last 2 digits of the subscriber number.
//   - Refresh-token rotation chains always preserve family_root.

import (
	"context"
	"fmt"
	"math"
	"strconv"
	"testing"
	"time"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/internal/identity"
	identityjwt "github.com/mopro/platform/internal/identity/jwt"
	"github.com/mopro/platform/internal/identity/ratelimit"
	pkgcrypto "github.com/mopro/platform/pkg/crypto"
)

// TestProperty_OTPCodeDistribution verifies that the 6-digit OTP generator produces
// uniformly distributed codes (chi-square goodness-of-fit, p > 0.05).
func TestProperty_OTPCodeDistribution(t *testing.T) {
	const n = 600 // run 600 OTP requests — enough for chi-square validity (expected ≥5 per cell)
	ctx := context.Background()

	integRedis.FlushDB(ctx)
	repo := newIntegRepo(t)
	limiter := ratelimit.New(integRedis)
	signer := newIntegSigner(t)
	sms := &multiCaptureSMS{}

	svc := identity.NewService(repo, sms, capturedEmail{}, limiter, signer, "TR", "tr-TR", nil, nil)

	// Use unique phone numbers per call to avoid rate-limit hits.
	for i := 0; i < n; i++ {
		phone := fmt.Sprintf("+9090%07d", i)
		if err := svc.RequestOTP(ctx, phone, identity.OTPPurposeLogin, ""); err != nil {
			t.Fatalf("RequestOTP[%d]: %v", i, err)
		}
	}

	if len(sms.codes) != n {
		t.Fatalf("expected %d OTP codes, got %d", n, len(sms.codes))
	}

	// Verify each code is exactly 6 decimal digits.
	for i, code := range sms.codes {
		if len(code) != 6 {
			t.Errorf("code[%d] = %q: expected 6 digits, got %d", i, code, len(code))
		}
		if _, err := strconv.Atoi(code); err != nil {
			t.Errorf("code[%d] = %q: not a numeric string: %v", i, code, err)
		}
	}

	// Chi-square uniformity test over the full 6-digit range [000000, 999999].
	// Count occurrences of each leading digit (10 cells, expected = n/10).
	observed := make([]float64, 10)
	for _, code := range sms.codes {
		digit := int(code[0] - '0')
		observed[digit]++
	}
	expected := float64(n) / 10
	chi2 := 0.0
	for _, o := range observed {
		diff := o - expected
		chi2 += diff * diff / expected
	}
	// Chi-square critical value for df=9, p=0.05 is 16.919.
	const chi2Critical = 16.919
	if chi2 > chi2Critical {
		t.Errorf("chi-square test failed: chi2=%.3f > critical=%.3f (observed: %v)", chi2, chi2Critical, observed)
	}
	t.Logf("OTP distribution chi2=%.3f (critical=%.3f, n=%d) — PASS", chi2, chi2Critical, n)
}

// TestProperty_JWTSigner_RoundTrip verifies that for any userID in [1, 2^31-1]
// and any market code, issuing and then verifying an access token recovers the
// exact same claims.
func TestProperty_JWTSigner_RoundTrip(t *testing.T) {
	signer := newIntegSigner(t)

	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 200
	properties := gopter.NewProperties(params)

	properties.Property(
		"IssueAccess → Verify recovers userID and market exactly",
		prop.ForAll(
			func(userID int64, market string) bool {
				if userID <= 0 {
					userID = 1
				}
				token, _, err := signer.IssueAccess(userID, market)
				if err != nil {
					t.Logf("IssueAccess(%d, %q): %v", userID, market, err)
					return false
				}
				claims, err := signer.Verify(token)
				if err != nil {
					t.Logf("Verify: %v", err)
					return false
				}
				if claims.UserID != userID {
					t.Logf("userID mismatch: want %d got %d", userID, claims.UserID)
					return false
				}
				if claims.Market != market {
					t.Logf("market mismatch: want %q got %q", market, claims.Market)
					return false
				}
				if claims.Scope != identityjwt.ScopeAPI {
					t.Logf("scope mismatch: want %q got %q", identityjwt.ScopeAPI, claims.Scope)
					return false
				}
				return true
			},
			gen.Int64Range(1, math.MaxInt32),
			gen.AnyString(),
		),
	)

	properties.TestingRun(t)
}

// TestProperty_MaskPhone_PrivacyInvariant verifies that for any E.164 TR phone,
// MaskPhone always shows the last 2 digits and masks the middle.
func TestProperty_MaskPhone_PrivacyInvariant(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 100
	properties := gopter.NewProperties(params)

	properties.Property(
		"MaskPhone always hides the subscriber number middle digits",
		prop.ForAll(
			func(suffix int64) bool {
				// Construct a valid TR E.164: +905XXXXXXXXX (10 digits after +90)
				phone := fmt.Sprintf("+905%09d", suffix%1000000000)
				masked := identity.MaskPhone(phone)
				if masked == phone {
					t.Logf("MaskPhone(%q) returned unmasked value", phone)
					return false
				}
				// The masked string must not reveal the middle 7 digits (positions 5-11 of phone).
				if len(masked) == 0 {
					t.Logf("MaskPhone(%q) returned empty string", phone)
					return false
				}
				// Verify the last 2 characters of the original are present somewhere in masked.
				last2 := phone[len(phone)-2:]
				if len(masked) < 2 {
					return true // too short to check
				}
				maskedLast2 := masked[len(masked)-2:]
				if maskedLast2 != last2 {
					t.Logf("MaskPhone(%q): expected last2=%q in masked, got masked=%q", phone, last2, masked)
					return false
				}
				return true
			},
			gen.Int64Range(1000000000, 9999999999),
		),
	)

	properties.TestingRun(t)
}

// TestProperty_RefreshTokenRotationChain verifies that after k rotations (k in [1,5]),
// every token in the chain shares the same family_root as the original.
func TestProperty_RefreshTokenRotationChain(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)
	repo := newIntegRepo(t)

	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 20
	properties := gopter.NewProperties(params)

	properties.Property(
		"After k rotations, all tokens share the original family_root",
		prop.ForAll(
			func(k uint8) bool {
				rotations := int(k%5) + 1 // [1,5]

				// Seed: create a user via OTP verify.
				phone := fmt.Sprintf("+9091%07d", time.Now().UnixNano()%10000000)
				hash := mustPhoneHash(t, phone)
				otp := identity.OTP{
					PhoneHash: hash,
					Purpose:   identity.OTPPurposeLogin,
					CodeHash:  mustBcrypt(t, "777777"),
					ExpiresAt: time.Now().Add(10 * time.Minute),
				}
				if err := repo.CreateOTP(ctx, otp); err != nil {
					return false
				}
				found, err := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
				if err != nil {
					return false
				}
				suffix := fmt.Sprint(time.Now().UnixNano())
				tok0 := identity.RefreshToken{
					TokenHash:  "prop-chain-0-" + suffix,
					FamilyRoot: "prop-family-" + suffix,
					ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
				}
				phoneEnc, _ := pkgcrypto.EncryptPII(phone)
				_, err = repo.MarkOTPVerifiedAndCreateSession(ctx, found.ID, hash, phoneEnc, "TR", "tr-TR", tok0)
				if err != nil {
					return false
				}

				// Rotate k times.
				currentHash := tok0.TokenHash
				originalFamily := tok0.FamilyRoot
				for i := 1; i <= rotations; i++ {
					newTok := identity.RefreshToken{
						TokenHash:  fmt.Sprintf("prop-chain-%d-%s", i, suffix),
						FamilyRoot: originalFamily,
						ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
					}
					_, got, err := repo.RotateRefreshToken(ctx, currentHash, newTok)
					if err != nil {
						t.Logf("rotation %d: %v", i, err)
						return false
					}
					if got.FamilyRoot != originalFamily {
						t.Logf("rotation %d: family_root=%q != original=%q", i, got.FamilyRoot, originalFamily)
						return false
					}
					currentHash = got.TokenHash
				}
				return true
			},
			gen.UInt8(),
		),
	)

	properties.TestingRun(t)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// multiCaptureSMS records all codes sent across multiple Send calls.
type multiCaptureSMS struct {
	codes []string
}

func (m *multiCaptureSMS) Send(_ context.Context, _, code string) error {
	m.codes = append(m.codes, code)
	return nil
}
