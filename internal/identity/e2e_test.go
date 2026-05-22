//go:build integration

package identity_test

// E2E (end-to-end) tests for the identity service.
// These wire a real PgxRepository + real RedisLimiter + in-memory SMS mock
// and exercise complete user journeys without mocking the service internals.
//
// Scenarios:
//   - Full OTP login → GetMe → UpdateMe flow
//   - Refresh-token theft detection (revoked token reuse revokes entire family)
//   - Step-up OTP flow
//   - Logout revokes token; subsequent refresh fails

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	identityjwt "github.com/mopro/platform/internal/identity/jwt"
	"github.com/mopro/platform/internal/identity/ratelimit"

	"github.com/mopro/platform/internal/identity"
)

// newE2ESvc builds a full-stack identity service backed by the integration DB and Redis.
func newE2ESvc(t *testing.T, sms *capturedSMS) identity.Service {
	t.Helper()
	repo := newIntegRepo(t)
	limiter := ratelimit.New(integRedis)
	signer := newIntegSigner(t)
	return identity.NewService(repo, sms, limiter, signer, "TR", "tr-TR", nil)
}

// e2ePhone generates a unique E.164 phone for each test to avoid DB collisions.
func e2ePhone(t *testing.T) string {
	t.Helper()
	return fmt.Sprintf("+9060%07d", time.Now().UnixNano()%10000000)
}

// loginUser performs a complete OTP request → verify and returns the TokenPair + service.
func loginUser(t *testing.T, svc identity.Service, sms *capturedSMS, phone string) identity.TokenPair {
	t.Helper()
	ctx := context.Background()
	if err := svc.RequestOTP(ctx, phone, identity.OTPPurposeLogin, ""); err != nil {
		t.Fatalf("RequestOTP(%q): %v", phone, err)
	}
	code := sms.code
	if code == "" {
		t.Fatal("SMS mock captured no code")
	}
	pair, err := svc.VerifyOTP(ctx, phone, identity.OTPPurposeLogin, code)
	if err != nil {
		t.Fatalf("VerifyOTP(%q, %q): %v", phone, code, err)
	}
	return pair
}

// TestE2E_FullLoginAndMeFlow covers the primary happy path:
// OTP request → OTP verify → GetMe → UpdateMe
func TestE2E_FullLoginAndMeFlow(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)

	sms := &capturedSMS{}
	svc := newE2ESvc(t, sms)
	phone := e2ePhone(t)

	pair := loginUser(t, svc, sms, phone)

	// Access token must be a valid JWT with scope=api.
	signer := newIntegSigner(t)
	claims, err := signer.Verify(pair.AccessToken)
	if err != nil {
		t.Fatalf("Verify access token: %v", err)
	}
	if claims.Scope != identityjwt.ScopeAPI {
		t.Errorf("expected scope %q, got %q", identityjwt.ScopeAPI, claims.Scope)
	}
	userID := claims.UserID
	if userID == 0 {
		t.Fatal("zero userID in claims")
	}

	// GetMe returns the user with active status.
	user, err := svc.GetMe(ctx, userID)
	if err != nil {
		t.Fatalf("GetMe: %v", err)
	}
	if user.Status != identity.StatusActive {
		t.Errorf("expected status active, got %q", user.Status)
	}

	// UpdateMe with a valid locale succeeds.
	name := "Ahmet Yılmaz"
	locale := "tr-TR"
	updated, err := svc.UpdateMe(ctx, userID, identity.UserUpdates{
		Name:   &name,
		Locale: &locale,
	})
	if err != nil {
		t.Fatalf("UpdateMe: %v", err)
	}
	if updated.Name != name {
		t.Errorf("expected name %q, got %q", name, updated.Name)
	}
}

// TestE2E_RefreshTokenTheft_DetectsAndRevokes is the canonical token-theft test.
// After one rotation, reusing the original (now-revoked) token must:
//  1. Return ErrTokenFamilyRevoked (not ErrTokenRevoked or a generic error).
//  2. Render the newly-rotated token also unusable (family is revoked atomically).
func TestE2E_RefreshTokenTheft_DetectsAndRevokes(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)

	sms := &capturedSMS{}
	svc := newE2ESvc(t, sms)
	phone := e2ePhone(t)

	// Step 1: login — get original token pair.
	original := loginUser(t, svc, sms, phone)

	// Step 2: legitimate client rotates the refresh token.
	rotated, err := svc.RefreshTokens(ctx, original.RefreshToken)
	if err != nil {
		t.Fatalf("RefreshTokens (legitimate): %v", err)
	}
	if rotated.RefreshToken == original.RefreshToken {
		t.Fatal("expected different refresh token after rotation")
	}

	// Step 3: attacker (or a stale client) reuses the original refresh token.
	// This must be detected as token theft and trigger family revocation.
	_, err = svc.RefreshTokens(ctx, original.RefreshToken)
	if !errors.Is(err, identity.ErrTokenFamilyRevoked) {
		t.Errorf("reusing revoked token: expected ErrTokenFamilyRevoked, got %v", err)
	}

	// Step 4: the legitimate new token must also be dead (family revoked atomically).
	_, err = svc.RefreshTokens(ctx, rotated.RefreshToken)
	if err == nil {
		t.Error("expected error on rotated token after family revocation, got nil")
	}
	if !errors.Is(err, identity.ErrTokenFamilyRevoked) && !errors.Is(err, identity.ErrTokenRevoked) {
		t.Errorf("expected family/token revocation error, got %v", err)
	}
}

// TestE2E_StepUpOTPFlow exercises the step-up authentication path.
func TestE2E_StepUpOTPFlow(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)

	sms := &capturedSMS{}
	svc := newE2ESvc(t, sms)
	phone := e2ePhone(t)

	pair := loginUser(t, svc, sms, phone)

	signer := newIntegSigner(t)
	claims, _ := signer.Verify(pair.AccessToken)
	userID := claims.UserID

	// Request a step-up OTP for the logged-in user.
	if err := svc.RequestStepUpOTP(ctx, userID, ""); err != nil {
		t.Fatalf("RequestStepUpOTP: %v", err)
	}
	stepUpCode := sms.code
	if stepUpCode == "" {
		t.Fatal("SMS mock captured no step-up code")
	}

	// Verify step-up OTP — returns a short-lived step-up token.
	stepUp, err := svc.VerifyStepUpOTP(ctx, userID, stepUpCode)
	if err != nil {
		t.Fatalf("VerifyStepUpOTP: %v", err)
	}
	if stepUp.Token == "" {
		t.Error("expected non-empty step-up token")
	}
	if stepUp.ExpiresAt.Before(time.Now()) {
		t.Error("step-up token expires_at is in the past")
	}

	// The step-up token must be a valid JWT with scope=high_sensitivity.
	stepClaims, err := signer.Verify(stepUp.Token)
	if err != nil {
		t.Fatalf("Verify step-up token: %v", err)
	}
	if stepClaims.Scope != identityjwt.ScopeStepUp {
		t.Errorf("expected scope %q, got %q", identityjwt.ScopeStepUp, stepClaims.Scope)
	}
	if stepClaims.UserID != userID {
		t.Errorf("expected userID %d, got %d", userID, stepClaims.UserID)
	}

	// Wrong code on step-up OTP returns ErrOTPInvalid.
	if err := svc.RequestStepUpOTP(ctx, userID, ""); err != nil {
		t.Fatalf("second RequestStepUpOTP: %v", err)
	}
	_, err = svc.VerifyStepUpOTP(ctx, userID, "000000")
	if !errors.Is(err, identity.ErrOTPInvalid) {
		t.Errorf("wrong step-up code: expected ErrOTPInvalid, got %v", err)
	}
}

// TestE2E_LogoutRevokesToken verifies that after logout the refresh token is dead.
func TestE2E_LogoutRevokesToken(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)

	sms := &capturedSMS{}
	svc := newE2ESvc(t, sms)
	phone := e2ePhone(t)

	pair := loginUser(t, svc, sms, phone)

	if err := svc.Logout(ctx, pair.RefreshToken); err != nil {
		t.Fatalf("Logout: %v", err)
	}

	// Refreshing after logout must fail with a token error.
	_, err := svc.RefreshTokens(ctx, pair.RefreshToken)
	if err == nil {
		t.Fatal("expected error after logout, got nil")
	}
	if !errors.Is(err, identity.ErrTokenRevoked) && !errors.Is(err, identity.ErrTokenNotFound) {
		t.Errorf("expected ErrTokenRevoked or ErrTokenNotFound, got %v", err)
	}
}

// TestE2E_DeleteMe_BlocksSubsequentLogin verifies that after DeleteMe,
// the same phone cannot OTP-verify into an active account.
func TestE2E_DeleteMe_BlocksSubsequentLogin(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)

	sms := &capturedSMS{}
	svc := newE2ESvc(t, sms)
	phone := e2ePhone(t)

	pair := loginUser(t, svc, sms, phone)

	signer := newIntegSigner(t)
	claims, _ := signer.Verify(pair.AccessToken)
	userID := claims.UserID

	if err := svc.DeleteMe(ctx, userID); err != nil {
		t.Fatalf("DeleteMe: %v", err)
	}

	// GetMe for the deleted user should return ErrUserDeleted.
	_, err := svc.GetMe(ctx, userID)
	if !errors.Is(err, identity.ErrUserDeleted) {
		t.Errorf("GetMe after delete: expected ErrUserDeleted, got %v", err)
	}

	// A new login attempt for the same phone should encounter ErrUserDeleted
	// when trying to create a new session (phone_hash already maps to deleted user).
	if err := svc.RequestOTP(ctx, phone, identity.OTPPurposeLogin, ""); err != nil {
		t.Fatalf("RequestOTP after delete: %v", err)
	}
	_, err = svc.VerifyOTP(ctx, phone, identity.OTPPurposeLogin, sms.code)
	if !errors.Is(err, identity.ErrUserDeleted) {
		t.Errorf("VerifyOTP after delete: expected ErrUserDeleted, got %v", err)
	}
}
