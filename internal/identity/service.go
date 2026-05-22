package identity

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"os"
	"regexp"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	pkgcrypto "github.com/mopro/platform/pkg/crypto"

	"github.com/mopro/platform/internal/identity/jwt"
	"github.com/mopro/platform/internal/identity/ratelimit"
	"github.com/mopro/platform/internal/identity/sms"
)

const (
	otpTTL          = 10 * time.Minute
	refreshTokenTTL = 30 * 24 * time.Hour
	bcryptCost      = 10
)

// serviceImpl is the concrete Service implementation.
type serviceImpl struct {
	repo          Repository
	sms           sms.Provider
	limiter       ratelimit.Limiter
	signer        jwt.Signer
	market        string
	defaultLocale string
	log           *slog.Logger
}

// NewService constructs a Service.
// Panics at startup if DEV_OTP_ACCEPT_ANY=true is combined with ENV=production.
func NewService(
	repo Repository,
	smsProv sms.Provider,
	limiter ratelimit.Limiter,
	signer jwt.Signer,
	market string,
	defaultLocale string,
	log *slog.Logger,
) Service {
	if os.Getenv("DEV_OTP_ACCEPT_ANY") == "true" && os.Getenv("ENV") == "production" {
		panic("identity: DEV_OTP_ACCEPT_ANY=true is forbidden on ENV=production")
	}
	if log == nil {
		log = slog.Default()
	}
	return &serviceImpl{
		repo:          repo,
		sms:           smsProv,
		limiter:       limiter,
		signer:        signer,
		market:        market,
		defaultLocale: defaultLocale,
		log:           log,
	}
}

// ── RequestOTP ────────────────────────────────────────────────────────────────

func (s *serviceImpl) RequestOTP(ctx context.Context, phoneE164 string, purpose string, clientIP string) error {
	if err := validatePhone(phoneE164); err != nil {
		return err
	}
	phoneHash, err := pkgcrypto.PhoneHash(phoneE164)
	if err != nil {
		return fmt.Errorf("identity: phone hash: %w", err)
	}
	if err := s.limiter.CheckOTPRequest(ctx, phoneHash, clientIP); err != nil {
		return mapRatelimitErr(err)
	}
	code, err := generateOTPCode()
	if err != nil {
		return fmt.Errorf("identity: generate otp: %w", err)
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(code), bcryptCost)
	if err != nil {
		return fmt.Errorf("identity: bcrypt otp: %w", err)
	}
	otp := OTP{
		PhoneHash: phoneHash,
		Purpose:   purpose,
		CodeHash:  string(hash),
		ExpiresAt: time.Now().Add(otpTTL),
	}
	if err := s.repo.CreateOTP(ctx, otp); err != nil {
		return fmt.Errorf("identity: store otp: %w", err)
	}
	if err := s.sms.Send(ctx, phoneE164, code); err != nil {
		s.log.Error("identity: sms send", "err", err, "purpose", purpose)
		return err
	}
	return nil
}

// ── VerifyOTP ─────────────────────────────────────────────────────────────────

func (s *serviceImpl) VerifyOTP(ctx context.Context, phoneE164 string, purpose string, code string) (TokenPair, error) {
	if err := validatePhone(phoneE164); err != nil {
		return TokenPair{}, err
	}
	phoneHash, err := pkgcrypto.PhoneHash(phoneE164)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: phone hash: %w", err)
	}

	// DEV backdoor — only active when DEV_OTP_ACCEPT_ANY=true AND ENV != production.
	if os.Getenv("DEV_OTP_ACCEPT_ANY") == "true" {
		return s.issueSessionForPhone(ctx, phoneHash, phoneE164)
	}

	otp, err := s.repo.FindLatestOTP(ctx, phoneHash, purpose)
	if errors.Is(err, ErrOTPNotFound) {
		return TokenPair{}, ErrOTPNotFound
	}
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: find otp: %w", err)
	}
	if time.Now().After(otp.ExpiresAt) {
		return TokenPair{}, ErrOTPExpired
	}
	if err := bcrypt.CompareHashAndPassword([]byte(otp.CodeHash), []byte(code)); err != nil {
		if ferr := s.limiter.RecordVerifyFailure(ctx, phoneHash); ferr != nil {
			return TokenPair{}, mapRatelimitErr(ferr)
		}
		return TokenPair{}, ErrOTPInvalid
	}
	if err := s.limiter.ResetVerifyFailures(ctx, phoneHash); err != nil {
		s.log.Warn("identity: reset verify failures", "err", err)
	}

	phoneEnc, err := pkgcrypto.EncryptPII(phoneE164)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: encrypt phone: %w", err)
	}
	rtc := newRefreshTokenCreation()
	user, err := s.repo.MarkOTPVerifiedAndCreateSession(
		ctx, otp.ID, phoneHash, phoneEnc, s.market, s.defaultLocale, rtc.token,
	)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: create session: %w", err)
	}
	if user.Status == StatusDeleted {
		return TokenPair{}, ErrUserDeleted
	}
	if user.Status == StatusSuspended {
		return TokenPair{}, ErrUserSuspended
	}
	accessToken, _, err := s.signer.IssueAccess(user.ID, s.market)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: issue access token: %w", err)
	}
	return TokenPair{
		AccessToken:      accessToken,
		RefreshToken:     rtc.raw,
		RefreshExpiresAt: rtc.token.ExpiresAt,
	}, nil
}

func (s *serviceImpl) issueSessionForPhone(ctx context.Context, phoneHash []byte, phoneE164 string) (TokenPair, error) {
	phoneEnc, err := pkgcrypto.EncryptPII(phoneE164)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: encrypt phone: %w", err)
	}
	rtc := newRefreshTokenCreation()
	// otpID=0: repo must tolerate 0 in dev mode (UPDATE affects 0 rows, which is OK in dev).
	user, err := s.repo.MarkOTPVerifiedAndCreateSession(
		ctx, 0, phoneHash, phoneEnc, s.market, s.defaultLocale, rtc.token,
	)
	if err != nil {
		return TokenPair{}, err
	}
	accessToken, _, err := s.signer.IssueAccess(user.ID, s.market)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: issue access token: %w", err)
	}
	return TokenPair{
		AccessToken:      accessToken,
		RefreshToken:     rtc.raw,
		RefreshExpiresAt: rtc.token.ExpiresAt,
	}, nil
}

// ── RefreshTokens ─────────────────────────────────────────────────────────────

func (s *serviceImpl) RefreshTokens(ctx context.Context, refreshToken string) (TokenPair, error) {
	currentHash := hashToken(refreshToken)
	// Build a new token; repo will override family_root with the predecessor's family_root.
	rtc := newRefreshTokenCreation()
	user, created, err := s.repo.RotateRefreshToken(ctx, currentHash, rtc.token)
	if err != nil {
		return TokenPair{}, err
	}
	if user.Status == StatusSuspended {
		return TokenPair{}, ErrUserSuspended
	}
	if user.Status == StatusDeleted {
		return TokenPair{}, ErrUserDeleted
	}
	accessToken, _, err := s.signer.IssueAccess(user.ID, s.market)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: issue access token: %w", err)
	}
	return TokenPair{
		AccessToken:      accessToken,
		RefreshToken:     rtc.raw, // raw value that maps to created.TokenHash
		RefreshExpiresAt: created.ExpiresAt,
	}, nil
}

// ── Logout ────────────────────────────────────────────────────────────────────

func (s *serviceImpl) Logout(ctx context.Context, refreshToken string) error {
	tokenHash := hashToken(refreshToken)
	err := s.repo.RevokeToken(ctx, tokenHash)
	if errors.Is(err, ErrTokenNotFound) {
		return nil // idempotent
	}
	return err
}

// ── GetMe / UpdateMe / DeleteMe ───────────────────────────────────────────────

func (s *serviceImpl) GetMe(ctx context.Context, userID int64) (User, error) {
	return s.repo.GetUser(ctx, userID)
}

func (s *serviceImpl) UpdateMe(ctx context.Context, userID int64, updates UserUpdates) (User, error) {
	if updates.Email != nil && *updates.Email != "" {
		if err := validateEmail(*updates.Email); err != nil {
			return User{}, err
		}
		enc, err := pkgcrypto.EncryptPII(*updates.Email)
		if err != nil {
			return User{}, fmt.Errorf("identity: encrypt email: %w", err)
		}
		updates.Email = &enc
	}
	if updates.Locale != nil {
		if err := validateLocale(*updates.Locale); err != nil {
			return User{}, err
		}
	}
	return s.repo.UpdateUser(ctx, userID, updates)
}

func (s *serviceImpl) DeleteMe(ctx context.Context, userID int64) error {
	return s.repo.SoftDeleteWithRevoke(ctx, userID)
}

// ── Step-up OTP ───────────────────────────────────────────────────────────────

func (s *serviceImpl) RequestStepUpOTP(ctx context.Context, userID int64, clientIP string) error {
	user, err := s.repo.GetUser(ctx, userID)
	if err != nil {
		return err
	}
	phoneE164, err := pkgcrypto.DecryptPII(user.PhoneEnc)
	if err != nil {
		return fmt.Errorf("identity: decrypt phone: %w", err)
	}
	return s.RequestOTP(ctx, phoneE164, OTPPurposeStepUp, clientIP)
}

func (s *serviceImpl) VerifyStepUpOTP(ctx context.Context, userID int64, code string) (StepUpToken, error) {
	user, err := s.repo.GetUser(ctx, userID)
	if err != nil {
		return StepUpToken{}, err
	}
	phoneE164, err := pkgcrypto.DecryptPII(user.PhoneEnc)
	if err != nil {
		return StepUpToken{}, fmt.Errorf("identity: decrypt phone: %w", err)
	}
	phoneHash, err := pkgcrypto.PhoneHash(phoneE164)
	if err != nil {
		return StepUpToken{}, fmt.Errorf("identity: phone hash: %w", err)
	}

	otp, err := s.repo.FindLatestOTP(ctx, phoneHash, OTPPurposeStepUp)
	if errors.Is(err, ErrOTPNotFound) {
		return StepUpToken{}, ErrOTPNotFound
	}
	if err != nil {
		return StepUpToken{}, err
	}
	if time.Now().After(otp.ExpiresAt) {
		return StepUpToken{}, ErrOTPExpired
	}
	if err := bcrypt.CompareHashAndPassword([]byte(otp.CodeHash), []byte(code)); err != nil {
		if ferr := s.limiter.RecordVerifyFailure(ctx, phoneHash); ferr != nil {
			return StepUpToken{}, mapRatelimitErr(ferr)
		}
		return StepUpToken{}, ErrOTPInvalid
	}
	_ = s.limiter.ResetVerifyFailures(ctx, phoneHash)
	// Mark as used so the step-up OTP cannot be replayed within its TTL.
	if err := s.repo.MarkOTPVerified(ctx, otp.ID); err != nil {
		return StepUpToken{}, fmt.Errorf("identity: mark step-up otp used: %w", err)
	}

	stepUpToken, expiresAt, err := s.signer.IssueStepUp(userID)
	if err != nil {
		return StepUpToken{}, fmt.Errorf("identity: issue step-up token: %w", err)
	}
	return StepUpToken{Token: stepUpToken, ExpiresAt: expiresAt}, nil
}

// ── RegisterDevice ────────────────────────────────────────────────────────────

func (s *serviceImpl) RegisterDevice(ctx context.Context, userID int64, info DeviceInfo) (Device, error) {
	return s.repo.CreateDevice(ctx, userID, info)
}

// ── helpers ───────────────────────────────────────────────────────────────────

var e164Re = regexp.MustCompile(`^\+[1-9]\d{7,14}$`)

func validatePhone(phone string) error {
	if !e164Re.MatchString(phone) {
		return ErrInvalidPhone
	}
	return nil
}

var localeRe = regexp.MustCompile(`^[a-z]{2,3}(-[A-Z]{2,4})?$`)

func validateLocale(locale string) error {
	if !localeRe.MatchString(locale) {
		return ErrInvalidLocale
	}
	return nil
}

var emailRe = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)

func validateEmail(email string) error {
	if email != "" && !emailRe.MatchString(strings.TrimSpace(email)) {
		return ErrInvalidEmail
	}
	return nil
}

// generateOTPCode returns a cryptographically-random 6-digit code (zero-padded).
func generateOTPCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// hashToken returns hex(SHA-256(raw)) for DB storage and lookup.
func hashToken(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(h[:])
}

// generateOpaqueToken returns 32 random bytes as a 64-char hex string.
func generateOpaqueToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// refreshTokenCreation bundles the raw opaque token with the domain record for creation.
type refreshTokenCreation struct {
	raw   string        // 64-char hex — returned to the client, never stored
	token RefreshToken  // stored in DB; token.TokenHash = SHA-256(raw)
}

// newRefreshTokenCreation generates a new opaque token + its DB record.
func newRefreshTokenCreation() refreshTokenCreation {
	raw := generateOpaqueToken()
	h := sha256.Sum256([]byte(raw))
	familyRoot := generateOpaqueToken() // first token in a new rotation chain
	return refreshTokenCreation{
		raw: raw,
		token: RefreshToken{
			TokenHash:  hex.EncodeToString(h[:]),
			FamilyRoot: familyRoot,
			ExpiresAt:  time.Now().Add(refreshTokenTTL),
		},
	}
}

// mapRatelimitErr converts ratelimit package errors to identity package sentinels.
func mapRatelimitErr(err error) error {
	switch {
	case errors.Is(err, ratelimit.ErrRateLimited):
		return ErrOTPRateLimitExceeded
	case errors.Is(err, ratelimit.ErrLocked):
		return ErrOTPVerifyLocked
	default:
		return err
	}
}
