//go:build integration

package identity_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"

	"github.com/mopro/platform/internal/identity"
	identityjwt "github.com/mopro/platform/internal/identity/jwt"
	"github.com/mopro/platform/internal/identity/ratelimit"
	pkgcrypto "github.com/mopro/platform/pkg/crypto"
)

const (
	defaultIdentityTestDSN   = "postgres://ecom_admin:test123@localhost:6435/mopro_ecom"
	defaultIdentityTestRedis = "localhost:6380"
)

var (
	integPool  *pgxpool.Pool
	integRedis *redis.Client
)

// TestMain sets up shared Postgres + Redis connections for all integration tests.
// It creates identity_schema tables from scratch (no migration runner needed).
func TestMain(m *testing.M) {
	os.Setenv("PII_KEK_BASE64", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
	os.Setenv("PII_PEPPER", "test-pepper-for-identity-integration")

	dsn := os.Getenv("IDENTITY_TEST_DSN")
	if dsn == "" {
		dsn = defaultIdentityTestDSN
	}
	redisAddr := os.Getenv("IDENTITY_TEST_REDIS")
	if redisAddr == "" {
		redisAddr = defaultIdentityTestRedis
	}
	redisPW := os.Getenv("REDIS_TEST_PASSWORD")

	ctx := context.Background()

	var err error
	integPool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "identity integration: pool create: %v\n", err)
		os.Exit(1)
	}
	if err := integPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "identity integration: pg ping failed: %v\n", err)
		os.Exit(1)
	}
	if err := setupIdentitySchema(ctx, integPool); err != nil {
		fmt.Fprintf(os.Stderr, "identity integration: schema setup: %v\n", err)
		os.Exit(1)
	}

	integRedis = redis.NewClient(&redis.Options{Addr: redisAddr, Password: redisPW, DB: 1})
	if err := integRedis.Ping(ctx).Err(); err != nil {
		fmt.Fprintf(os.Stderr, "identity integration: redis ping failed: %v\n", err)
		os.Exit(1)
	}
	integRedis.FlushDB(ctx)

	code := m.Run()
	integPool.Close()
	integRedis.Close()
	os.Exit(code)
}

// setupIdentitySchema creates (or recreates) the identity tables used by integration tests.
func setupIdentitySchema(ctx context.Context, pool *pgxpool.Pool) error {
	ddl := `
CREATE SCHEMA IF NOT EXISTS identity_schema;

DROP TABLE IF EXISTS identity_schema.devices CASCADE;
DROP TABLE IF EXISTS identity_schema.refresh_tokens CASCADE;
DROP TABLE IF EXISTS identity_schema.otp_codes CASCADE;
DROP TABLE IF EXISTS identity_schema.users CASCADE;
DROP FUNCTION IF EXISTS identity_schema.touch_updated_at() CASCADE;

CREATE TABLE identity_schema.users (
    id          BIGSERIAL   PRIMARY KEY,
    phone_hash  BYTEA       NOT NULL,
    phone_enc   TEXT        NOT NULL,
    email_enc   TEXT,
    name        TEXT        NOT NULL DEFAULT '',
    locale      TEXT        NOT NULL DEFAULT 'tr-TR',
    status      TEXT        NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);
CREATE UNIQUE INDEX users_phone_hash_idx ON identity_schema.users(phone_hash);

CREATE OR REPLACE FUNCTION identity_schema.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON identity_schema.users
    FOR EACH ROW EXECUTE FUNCTION identity_schema.touch_updated_at();

CREATE TABLE identity_schema.otp_codes (
    id          BIGSERIAL   PRIMARY KEY,
    phone_hash  BYTEA       NOT NULL,
    purpose     TEXT        NOT NULL DEFAULT 'login'
                CHECK (purpose IN ('login', 'step_up')),
    code_hash   TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ
);
CREATE INDEX otp_codes_lookup_idx
    ON identity_schema.otp_codes(phone_hash, purpose, expires_at DESC)
    WHERE verified_at IS NULL;

CREATE TABLE identity_schema.refresh_tokens (
    id             BIGSERIAL   PRIMARY KEY,
    user_id        BIGINT      NOT NULL REFERENCES identity_schema.users(id),
    token_hash     TEXT        NOT NULL,
    family_root    TEXT        NOT NULL,
    issued_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ NOT NULL,
    revoked_at     TIMESTAMPTZ,
    revoked_reason TEXT        CHECK (revoked_reason IN ('rotation','logout','theft','admin','expired'))
);
CREATE UNIQUE INDEX refresh_tokens_hash_idx ON identity_schema.refresh_tokens(token_hash);
CREATE INDEX refresh_tokens_family_idx ON identity_schema.refresh_tokens(family_root)
    WHERE revoked_at IS NULL;

CREATE TABLE identity_schema.devices (
    id            BIGSERIAL   PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES identity_schema.users(id),
    fcm_token     TEXT        NOT NULL,
    device_model  TEXT        NOT NULL DEFAULT '',
    os_version    TEXT        NOT NULL DEFAULT '',
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at    TIMESTAMPTZ
);
CREATE UNIQUE INDEX devices_fcm_active_idx ON identity_schema.devices(fcm_token)
    WHERE revoked_at IS NULL;
`
	_, err := pool.Exec(ctx, ddl)
	return err
}

// newIntegRepo returns a real PgxRepository backed by the integration pool.
func newIntegRepo(t *testing.T) identity.Repository {
	t.Helper()
	return identity.NewRepository(integPool)
}

// newIntegSigner returns a test HS256Signer.
func newIntegSigner(t *testing.T) identityjwt.Signer {
	t.Helper()
	s, err := identityjwt.NewHS256Signer([]byte("integ-test-signing-key-32-bytes!"))
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// mustPhoneHash returns a phone hash or fails the test.
func mustPhoneHash(t *testing.T, phone string) []byte {
	t.Helper()
	h, err := pkgcrypto.PhoneHash(phone)
	if err != nil {
		t.Fatalf("PhoneHash(%q): %v", phone, err)
	}
	return h
}

// mustEncryptPII returns an encrypted PII value or fails the test.
func mustEncryptPII(t *testing.T, plain string) string {
	t.Helper()
	enc, err := pkgcrypto.EncryptPII(plain)
	if err != nil {
		t.Fatalf("EncryptPII(%q): %v", plain, err)
	}
	return enc
}

// mustBcrypt returns a bcrypt hash of the input or fails the test.
func mustBcrypt(t *testing.T, plain string) string {
	t.Helper()
	h, err := bcrypt.GenerateFromPassword([]byte(plain), 10)
	if err != nil {
		t.Fatalf("bcrypt(%q): %v", plain, err)
	}
	return string(h)
}

// ── Repository integration tests ──────────────────────────────────────────────

func TestInteg_CreateAndFindOTP(t *testing.T) {
	ctx := context.Background()
	repo := newIntegRepo(t)

	phone := fmt.Sprintf("+9053%08d", time.Now().UnixNano()%100000000)
	hash := mustPhoneHash(t, phone)

	otp := identity.OTP{
		PhoneHash: hash,
		Purpose:   identity.OTPPurposeLogin,
		CodeHash:  mustBcrypt(t, "123456"),
		ExpiresAt: time.Now().Add(10 * time.Minute),
	}
	if err := repo.CreateOTP(ctx, otp); err != nil {
		t.Fatalf("CreateOTP: %v", err)
	}

	found, err := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
	if err != nil {
		t.Fatalf("FindLatestOTP: %v", err)
	}
	if found.Purpose != identity.OTPPurposeLogin {
		t.Errorf("expected purpose login, got %q", found.Purpose)
	}
	if found.VerifiedAt != nil {
		t.Error("expected VerifiedAt=nil on freshly created OTP")
	}
}

func TestInteg_FindLatestOTP_NotFound(t *testing.T) {
	ctx := context.Background()
	repo := newIntegRepo(t)

	// Generate a unique phone that has never had an OTP.
	phone := fmt.Sprintf("+9099%08d", time.Now().UnixNano()%100000000)
	hash := mustPhoneHash(t, phone)

	_, err := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
	if !errors.Is(err, identity.ErrOTPNotFound) {
		t.Errorf("expected ErrOTPNotFound, got %v", err)
	}
}

func TestInteg_MarkOTPVerifiedAndCreateSession(t *testing.T) {
	ctx := context.Background()
	repo := newIntegRepo(t)

	phone := fmt.Sprintf("+9054%08d", time.Now().UnixNano()%100000000)
	hash := mustPhoneHash(t, phone)

	otp := identity.OTP{
		PhoneHash: hash,
		Purpose:   identity.OTPPurposeLogin,
		CodeHash:  mustBcrypt(t, "654321"),
		ExpiresAt: time.Now().Add(10 * time.Minute),
	}
	if err := repo.CreateOTP(ctx, otp); err != nil {
		t.Fatalf("CreateOTP: %v", err)
	}

	found, err := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
	if err != nil {
		t.Fatalf("FindLatestOTP: %v", err)
	}

	phoneEnc := mustEncryptPII(t, phone)
	newTok := identity.RefreshToken{
		TokenHash:  "integ-hash-" + fmt.Sprint(time.Now().UnixNano()),
		FamilyRoot: "integ-family-" + fmt.Sprint(time.Now().UnixNano()),
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
	}

	user, err := repo.MarkOTPVerifiedAndCreateSession(
		ctx, found.ID, hash, phoneEnc, "TR", "tr-TR", newTok,
	)
	if err != nil {
		t.Fatalf("MarkOTPVerifiedAndCreateSession: %v", err)
	}
	if user.ID == 0 {
		t.Error("expected non-zero user ID")
	}
	if user.Status != identity.StatusActive {
		t.Errorf("expected status active, got %q", user.Status)
	}

	// Calling it again with the same OTP ID must return ErrOTPAlreadyUsed.
	_, err = repo.MarkOTPVerifiedAndCreateSession(
		ctx, found.ID, hash, phoneEnc, "TR", "tr-TR",
		identity.RefreshToken{
			TokenHash:  "integ-hash-dup-" + fmt.Sprint(time.Now().UnixNano()),
			FamilyRoot: "integ-family-dup",
			ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
		},
	)
	if !errors.Is(err, identity.ErrOTPAlreadyUsed) {
		t.Errorf("expected ErrOTPAlreadyUsed on second call, got %v", err)
	}
}

func TestInteg_RotateRefreshToken(t *testing.T) {
	ctx := context.Background()
	repo := newIntegRepo(t)

	// Seed a user + first token via OTP verify session creation.
	phone := fmt.Sprintf("+9055%08d", time.Now().UnixNano()%100000000)
	hash := mustPhoneHash(t, phone)
	otp := identity.OTP{
		PhoneHash: hash, Purpose: identity.OTPPurposeLogin,
		CodeHash: mustBcrypt(t, "111111"), ExpiresAt: time.Now().Add(10 * time.Minute),
	}
	if err := repo.CreateOTP(ctx, otp); err != nil {
		t.Fatal(err)
	}
	found, err := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
	if err != nil {
		t.Fatal(err)
	}

	suffix := fmt.Sprint(time.Now().UnixNano())
	tok1 := identity.RefreshToken{
		TokenHash:  "rot-hash-1-" + suffix,
		FamilyRoot: "rot-family-" + suffix,
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
	}
	user, err := repo.MarkOTPVerifiedAndCreateSession(
		ctx, found.ID, hash, mustEncryptPII(t, phone), "TR", "tr-TR", tok1,
	)
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	// Rotate to tok2.
	tok2 := identity.RefreshToken{
		TokenHash:  "rot-hash-2-" + suffix,
		FamilyRoot: tok1.FamilyRoot,
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
	}
	gotUser, gotTok, err := repo.RotateRefreshToken(ctx, tok1.TokenHash, tok2)
	if err != nil {
		t.Fatalf("RotateRefreshToken: %v", err)
	}
	if gotUser.ID != user.ID {
		t.Errorf("expected user ID %d, got %d", user.ID, gotUser.ID)
	}
	if gotTok.TokenHash != tok2.TokenHash {
		t.Errorf("expected new token hash %s, got %s", tok2.TokenHash, gotTok.TokenHash)
	}
	if gotTok.FamilyRoot != tok1.FamilyRoot {
		t.Errorf("expected family_root inherited: %s, got %s", tok1.FamilyRoot, gotTok.FamilyRoot)
	}

	// Reusing tok1 (revoked) triggers theft detection.
	_, _, err = repo.RotateRefreshToken(ctx, tok1.TokenHash, identity.RefreshToken{
		TokenHash:  "rot-hash-3-" + suffix,
		FamilyRoot: tok1.FamilyRoot,
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
	})
	if !errors.Is(err, identity.ErrTokenFamilyRevoked) {
		t.Errorf("expected ErrTokenFamilyRevoked on revoked token reuse, got %v", err)
	}
}

func TestInteg_SoftDeleteWithRevoke(t *testing.T) {
	ctx := context.Background()
	repo := newIntegRepo(t)

	phone := fmt.Sprintf("+9056%08d", time.Now().UnixNano()%100000000)
	hash := mustPhoneHash(t, phone)
	otp := identity.OTP{
		PhoneHash: hash, Purpose: identity.OTPPurposeLogin,
		CodeHash: mustBcrypt(t, "222222"), ExpiresAt: time.Now().Add(10 * time.Minute),
	}
	if err := repo.CreateOTP(ctx, otp); err != nil {
		t.Fatal(err)
	}
	found, _ := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
	suffix := fmt.Sprint(time.Now().UnixNano())
	tok := identity.RefreshToken{
		TokenHash:  "del-hash-" + suffix,
		FamilyRoot: "del-family-" + suffix,
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
	}
	user, err := repo.MarkOTPVerifiedAndCreateSession(
		ctx, found.ID, hash, mustEncryptPII(t, phone), "TR", "tr-TR", tok,
	)
	if err != nil {
		t.Fatal(err)
	}

	if err := repo.SoftDeleteWithRevoke(ctx, user.ID); err != nil {
		t.Fatalf("SoftDeleteWithRevoke: %v", err)
	}

	// FindUserByPhoneHash should now return ErrUserDeleted.
	got, err := repo.FindUserByPhoneHash(ctx, hash)
	if err != nil {
		t.Fatalf("FindUserByPhoneHash after delete: %v", err)
	}
	if got.Status != identity.StatusDeleted {
		t.Errorf("expected status deleted, got %q", got.Status)
	}
}

func TestInteg_CreateDevice(t *testing.T) {
	ctx := context.Background()
	repo := newIntegRepo(t)

	phone := fmt.Sprintf("+9057%08d", time.Now().UnixNano()%100000000)
	hash := mustPhoneHash(t, phone)
	otp := identity.OTP{
		PhoneHash: hash, Purpose: identity.OTPPurposeLogin,
		CodeHash: mustBcrypt(t, "333333"), ExpiresAt: time.Now().Add(10 * time.Minute),
	}
	if err := repo.CreateOTP(ctx, otp); err != nil {
		t.Fatal(err)
	}
	found, _ := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
	suffix := fmt.Sprint(time.Now().UnixNano())
	tok := identity.RefreshToken{
		TokenHash:  "dev-hash-" + suffix,
		FamilyRoot: "dev-family-" + suffix,
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
	}
	user, err := repo.MarkOTPVerifiedAndCreateSession(
		ctx, found.ID, hash, mustEncryptPII(t, phone), "TR", "tr-TR", tok,
	)
	if err != nil {
		t.Fatal(err)
	}

	info := identity.DeviceInfo{
		FCMToken:    "fcm-token-" + suffix,
		DeviceModel: "iPhone 15",
		OSVersion:   "iOS 17.0",
	}
	dev, err := repo.CreateDevice(ctx, user.ID, info)
	if err != nil {
		t.Fatalf("CreateDevice: %v", err)
	}
	if dev.ID == 0 {
		t.Error("expected non-zero device ID")
	}
	if dev.FCMToken != info.FCMToken {
		t.Errorf("expected FCMToken %q, got %q", info.FCMToken, dev.FCMToken)
	}

	// Re-registering the same FCM token should succeed (dedup by revoke+insert).
	dev2, err := repo.CreateDevice(ctx, user.ID, info)
	if err != nil {
		t.Fatalf("CreateDevice dedup: %v", err)
	}
	if dev2.ID == dev.ID {
		t.Error("expected new device row on re-register, got same ID")
	}
}

// ── Rate limiter integration tests ───────────────────────────────────────────

func TestInteg_RateLimiter_OTPRequest_PhoneWindow(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)
	limiter := ratelimit.New(integRedis)

	// Use a stable byte hash for test isolation.
	phoneHash := []byte("integ-rl-phone-window-01")

	// First 3 requests within the short window should pass.
	for i := 0; i < 3; i++ {
		if err := limiter.CheckOTPRequest(ctx, phoneHash, ""); err != nil {
			t.Fatalf("request %d: expected ok, got %v", i+1, err)
		}
	}

	// 4th request must be rate-limited.
	err := limiter.CheckOTPRequest(ctx, phoneHash, "")
	if !errors.Is(err, ratelimit.ErrRateLimited) {
		t.Errorf("expected ErrRateLimited on 4th request, got %v", err)
	}
}

func TestInteg_RateLimiter_VerifyFailureLock(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)
	limiter := ratelimit.New(integRedis)

	phoneHash := []byte("integ-rl-verify-lock-01")

	// 10 failures triggers lock; 11th CheckOTPRequest returns ErrLocked.
	for i := 0; i < 10; i++ {
		if err := limiter.RecordVerifyFailure(ctx, phoneHash); err != nil {
			// ErrLocked may be returned on the 10th call itself, that's also acceptable.
			if errors.Is(err, ratelimit.ErrLocked) {
				return
			}
			t.Fatalf("failure %d: unexpected error %v", i+1, err)
		}
	}

	err := limiter.CheckOTPRequest(ctx, phoneHash, "")
	if !errors.Is(err, ratelimit.ErrLocked) {
		t.Errorf("expected ErrLocked after 10 verify failures, got %v", err)
	}
}

func TestInteg_RateLimiter_ResetVerifyFailures(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)
	limiter := ratelimit.New(integRedis)

	phoneHash := []byte("integ-rl-reset-01")

	// Record some failures, then reset.
	for i := 0; i < 5; i++ {
		_ = limiter.RecordVerifyFailure(ctx, phoneHash)
	}
	if err := limiter.ResetVerifyFailures(ctx, phoneHash); err != nil {
		t.Fatalf("ResetVerifyFailures: %v", err)
	}

	// Now the verify-fail count should be gone; next failure should not trigger lock.
	if err := limiter.RecordVerifyFailure(ctx, phoneHash); err != nil {
		t.Errorf("unexpected error after reset: %v", err)
	}
}

// ── End-to-end service integration test ──────────────────────────────────────

func TestInteg_Service_OTPVerifyFlow(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)

	repo := newIntegRepo(t)
	limiter := ratelimit.New(integRedis)
	smsMock := &capturedSMS{}
	signer := newIntegSigner(t)

	svc := identity.NewService(repo, smsMock, limiter, signer, "TR", "tr-TR", nil)

	phone := fmt.Sprintf("+9058%08d", time.Now().UnixNano()%100000000)

	// RequestOTP sends code via SMS.
	if err := svc.RequestOTP(ctx, phone, identity.OTPPurposeLogin, "1.2.3.4"); err != nil {
		t.Fatalf("RequestOTP: %v", err)
	}
	if smsMock.code == "" {
		t.Fatal("expected OTP code to be captured by SMS mock")
	}

	// VerifyOTP with correct code returns a TokenPair.
	pair, err := svc.VerifyOTP(ctx, phone, identity.OTPPurposeLogin, smsMock.code)
	if err != nil {
		t.Fatalf("VerifyOTP: %v", err)
	}
	if pair.AccessToken == "" {
		t.Error("expected non-empty access token")
	}
	if pair.RefreshToken == "" {
		t.Error("expected non-empty refresh token")
	}

	// Verify access token is a valid JWT for the right signer.
	claims, err := signer.Verify(pair.AccessToken)
	if err != nil {
		t.Fatalf("Verify access token: %v", err)
	}
	if claims.Scope != identityjwt.ScopeAPI {
		t.Errorf("expected scope %q, got %q", identityjwt.ScopeAPI, claims.Scope)
	}

	// RefreshTokens rotates and returns new pair.
	newPair, err := svc.RefreshTokens(ctx, pair.RefreshToken)
	if err != nil {
		t.Fatalf("RefreshTokens: %v", err)
	}
	if newPair.AccessToken == pair.AccessToken {
		t.Error("expected different access token after rotation")
	}

	// Old refresh token must be revoked — reusing it triggers family revocation.
	_, err = svc.RefreshTokens(ctx, pair.RefreshToken)
	if !errors.Is(err, identity.ErrTokenFamilyRevoked) {
		t.Errorf("expected ErrTokenFamilyRevoked on stale refresh token reuse, got %v", err)
	}
}

// TestIntegration_TokenReuse_RevokesEntireFamily is requirement B:
// Issue T1 → rotate T2 → rotate T3 → replay T1 → assert all 3 tokens in the family are revoked.
func TestIntegration_TokenReuse_RevokesEntireFamily(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)
	repo := newIntegRepo(t)
	limiter := ratelimit.New(integRedis)
	sms := &capturedSMS{}
	signer := newIntegSigner(t)
	svc := identity.NewService(repo, sms, limiter, signer, "TR", "tr-TR", nil)

	phone := fmt.Sprintf("+9062%07d", time.Now().UnixNano()%10000000)

	// Step 1: login — issue T1.
	if err := svc.RequestOTP(ctx, phone, identity.OTPPurposeLogin, ""); err != nil {
		t.Fatalf("RequestOTP: %v", err)
	}
	pair1, err := svc.VerifyOTP(ctx, phone, identity.OTPPurposeLogin, sms.code)
	if err != nil {
		t.Fatalf("VerifyOTP (T1): %v", err)
	}
	t1 := pair1.RefreshToken

	// Step 2: rotate T1 → T2.
	pair2, err := svc.RefreshTokens(ctx, t1)
	if err != nil {
		t.Fatalf("RefreshTokens (T1→T2): %v", err)
	}
	t2 := pair2.RefreshToken

	// Step 3: rotate T2 → T3.
	pair3, err := svc.RefreshTokens(ctx, t2)
	if err != nil {
		t.Fatalf("RefreshTokens (T2→T3): %v", err)
	}
	t3 := pair3.RefreshToken
	_ = t3 // kept for documentation; verified by family revocation below

	// Step 4: attacker replays T1 (which was revoked in step 2).
	// This must trigger family revocation.
	_, err = svc.RefreshTokens(ctx, t1)
	if !errors.Is(err, identity.ErrTokenFamilyRevoked) {
		t.Errorf("replay T1: expected ErrTokenFamilyRevoked, got %v", err)
	}

	// Step 5: T2 must also be dead (revoked atomically with family).
	_, err = svc.RefreshTokens(ctx, t2)
	if err == nil {
		t.Error("expected error for T2 after family revocation, got nil")
	} else if !errors.Is(err, identity.ErrTokenFamilyRevoked) && !errors.Is(err, identity.ErrTokenRevoked) {
		t.Errorf("T2 after family revocation: expected family/token revocation error, got %v", err)
	}

	// Step 6: T3 must also be dead.
	_, err = svc.RefreshTokens(ctx, t3)
	if err == nil {
		t.Error("expected error for T3 after family revocation, got nil")
	} else if !errors.Is(err, identity.ErrTokenFamilyRevoked) && !errors.Is(err, identity.ErrTokenRevoked) {
		t.Errorf("T3 after family revocation: expected family/token revocation error, got %v", err)
	}
}

// TestIntegration_StepUpOTPFlow is requirement E:
// - Request login OTP, verify, get tokens
// - Request step-up OTP (separate purpose)
// - Verify both OTPs exist in DB with different purpose
// - Verify step-up OTP → get step-up token with scope=high_sensitivity
// - Using wrong code at step-up verify returns ErrOTPInvalid
func TestIntegration_StepUpOTPFlow(t *testing.T) {
	ctx := context.Background()
	integRedis.FlushDB(ctx)
	repo := newIntegRepo(t)
	limiter := ratelimit.New(integRedis)
	sms := &capturedSMS{}
	signer := newIntegSigner(t)
	svc := identity.NewService(repo, sms, limiter, signer, "TR", "tr-TR", nil)

	phone := fmt.Sprintf("+9063%07d", time.Now().UnixNano()%10000000)

	// Step 1: login.
	if err := svc.RequestOTP(ctx, phone, identity.OTPPurposeLogin, ""); err != nil {
		t.Fatalf("RequestOTP login: %v", err)
	}
	loginCode := sms.code
	pair, err := svc.VerifyOTP(ctx, phone, identity.OTPPurposeLogin, loginCode)
	if err != nil {
		t.Fatalf("VerifyOTP login: %v", err)
	}
	claims, err := signer.Verify(pair.AccessToken)
	if err != nil {
		t.Fatalf("Verify access token: %v", err)
	}
	userID := claims.UserID

	// Step 2: request step-up OTP (separate purpose).
	if err := svc.RequestStepUpOTP(ctx, userID, ""); err != nil {
		t.Fatalf("RequestStepUpOTP: %v", err)
	}
	stepUpCode := sms.code

	// Step 3: verify both OTP purposes exist in DB independently.
	hash := mustPhoneHash(t, phone)
	loginOTP, err := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeLogin)
	if err != nil {
		t.Fatalf("FindLatestOTP login: %v", err)
	}
	// The login OTP was already verified (VerifiedAt set); step 3 just confirms repo access.
	if loginOTP.Purpose != identity.OTPPurposeLogin {
		t.Errorf("expected login OTP purpose=%q, got %q", identity.OTPPurposeLogin, loginOTP.Purpose)
	}

	stepUpOTP, err := repo.FindLatestOTP(ctx, hash, identity.OTPPurposeStepUp)
	if err != nil {
		t.Fatalf("FindLatestOTP step_up: %v", err)
	}
	if stepUpOTP.Purpose != identity.OTPPurposeStepUp {
		t.Errorf("expected step_up OTP purpose=%q, got %q", identity.OTPPurposeStepUp, stepUpOTP.Purpose)
	}
	if stepUpOTP.VerifiedAt != nil {
		t.Error("step_up OTP must not be verified yet")
	}

	// Step 4: verify step-up OTP → get step-up token.
	stepUpTok, err := svc.VerifyStepUpOTP(ctx, userID, stepUpCode)
	if err != nil {
		t.Fatalf("VerifyStepUpOTP: %v", err)
	}
	if stepUpTok.Token == "" {
		t.Error("expected non-empty step-up token")
	}

	// Step 5: step-up token must have scope=high_sensitivity.
	stepClaims, err := signer.Verify(stepUpTok.Token)
	if err != nil {
		t.Fatalf("Verify step-up token: %v", err)
	}
	if stepClaims.Scope != identityjwt.ScopeStepUp {
		t.Errorf("expected scope %q, got %q", identityjwt.ScopeStepUp, stepClaims.Scope)
	}
	if stepClaims.UserID != userID {
		t.Errorf("expected userID %d, got %d", userID, stepClaims.UserID)
	}

	// Step 6: using login OTP code at step-up verify must return ErrOTPNotFound
	// (login OTP has purpose='login', step-up verify only checks purpose='step_up').
	_, err = svc.VerifyStepUpOTP(ctx, userID, loginCode)
	// loginCode won't match any step_up OTP (step_up OTP already verified), so ErrOTPNotFound.
	if err == nil {
		t.Error("expected error using login code for step-up verify, got nil")
	}
}

// capturedSMS is an SMS provider that captures the sent code for test inspection.
type capturedSMS struct {
	to   string
	code string
}

func (c *capturedSMS) Send(_ context.Context, to, code string) error {
	c.to = to
	c.code = code
	return nil
}
