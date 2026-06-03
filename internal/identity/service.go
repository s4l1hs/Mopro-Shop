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
	"regexp"
	"strings"
	"time"
	"unicode"

	"golang.org/x/crypto/bcrypt"

	pkgcrypto "github.com/mopro/platform/pkg/crypto"
	"github.com/mopro/platform/pkg/metrics"

	"github.com/mopro/platform/internal/identity/email"
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
	repo            Repository
	sms             sms.Provider
	emailProv       email.Provider
	limiter         ratelimit.Limiter
	signer          jwt.Signer
	market          string
	defaultLocale   string
	log             *slog.Logger
	biz             *metrics.BusinessMetrics // nil disables business KPI counters
	devOTPAcceptAny bool                     // A-003: dev OTP backdoor (injected; was os.Getenv("DEV_OTP_ACCEPT_ANY"))
}

// Option configures NewService. A-003: replaces the DEV_OTP_ACCEPT_ANY / ENV env reads.
type Option func(*serviceConfig)

type serviceConfig struct {
	devOTPAcceptAny bool
	inProduction    bool
}

// WithDevOTPBypass enables the dev OTP backdoor (accept any OTP) and tells NewService
// whether the process is in production. NewService panics if the backdoor is enabled in
// production (the startup invariant, preserved). The caller (cmd/core-svc/main.go) reads
// DEV_OTP_ACCEPT_ANY + ENV and passes the values. No option = backdoor off (safe default).
func WithDevOTPBypass(acceptAny, inProduction bool) Option {
	return func(c *serviceConfig) {
		c.devOTPAcceptAny = acceptAny
		c.inProduction = inProduction
	}
}

// NewService constructs a Service.
// Panics at startup if the dev OTP bypass is enabled in production (see WithDevOTPBypass).
// biz is optional (nil disables business KPI metrics).
func NewService(
	repo Repository,
	smsProv sms.Provider,
	emailProv email.Provider,
	limiter ratelimit.Limiter,
	signer jwt.Signer,
	market string,
	defaultLocale string,
	log *slog.Logger,
	biz *metrics.BusinessMetrics,
	opts ...Option,
) Service {
	var cfg serviceConfig
	for _, o := range opts {
		o(&cfg)
	}
	if cfg.devOTPAcceptAny && cfg.inProduction {
		panic("identity: DEV_OTP_ACCEPT_ANY=true is forbidden on ENV=production")
	}
	if log == nil {
		log = slog.Default()
	}
	return &serviceImpl{
		devOTPAcceptAny: cfg.devOTPAcceptAny,
		repo:            repo,
		sms:             smsProv,
		emailProv:       emailProv,
		limiter:         limiter,
		signer:          signer,
		market:          market,
		defaultLocale:   defaultLocale,
		log:             log,
		biz:             biz,
	}
}

// ── RequestOTP ────────────────────────────────────────────────────────────────

func (s *serviceImpl) RequestOTP(ctx context.Context, phoneE164 string, purpose string, clientIP string) error {
	s.biz.IncOTPRequest("core-svc", purpose)
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

	// DEV backdoor — only active when the dev OTP bypass was enabled at construction
	// (WithDevOTPBypass); NewService forbids it in production. A-003: was os.Getenv.
	if s.devOTPAcceptAny {
		return s.issueSessionForPhone(ctx, phoneHash, phoneE164)
	}

	otp, err := s.repo.FindLatestOTP(ctx, phoneHash, purpose)
	if errors.Is(err, ErrOTPNotFound) {
		s.biz.IncOTPVerifyOutcome("core-svc", "not_found")
		return TokenPair{}, ErrOTPNotFound
	}
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: find otp: %w", err)
	}
	if time.Now().After(otp.ExpiresAt) {
		s.biz.IncOTPVerifyOutcome("core-svc", "expired")
		return TokenPair{}, ErrOTPExpired
	}
	if err := bcrypt.CompareHashAndPassword([]byte(otp.CodeHash), []byte(code)); err != nil {
		if ferr := s.limiter.RecordVerifyFailure(ctx, phoneHash); ferr != nil {
			s.biz.IncOTPVerifyOutcome("core-svc", "rate_limited")
			return TokenPair{}, mapRatelimitErr(ferr)
		}
		s.biz.IncOTPVerifyOutcome("core-svc", "invalid")
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
		s.biz.IncOTPVerifyOutcome("core-svc", "deleted")
		return TokenPair{}, ErrUserDeleted
	}
	if user.Status == StatusSuspended {
		s.biz.IncOTPVerifyOutcome("core-svc", "suspended")
		return TokenPair{}, ErrUserSuspended
	}
	accessToken, _, err := s.signer.IssueAccess(user.ID, s.market)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: issue access token: %w", err)
	}
	s.biz.IncOTPVerifyOutcome("core-svc", "success")
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
	u, err := s.repo.GetUser(ctx, userID)
	if err != nil {
		return User{}, err
	}
	// User-state-consumer discipline: reject soft-deleted users (mirrors the
	// session flows at VerifyOTP/RefreshTokens/LoginEmail). The repo returns
	// deleted rows by design; the service owns the policy. See CONTRIBUTING.
	if u.Status == StatusDeleted {
		return User{}, ErrUserDeleted
	}
	return u, nil
}

func (s *serviceImpl) UpdateMe(ctx context.Context, userID int64, updates UserUpdates) (User, error) {
	if cur, err := s.repo.GetUser(ctx, userID); err != nil {
		return User{}, err
	} else if cur.Status == StatusDeleted {
		return User{}, ErrUserDeleted
	}
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
	if user.Status == StatusDeleted {
		return ErrUserDeleted
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
	if user.Status == StatusDeleted {
		return StepUpToken{}, ErrUserDeleted
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

// validatePassword enforces: ≥8 chars, ≥1 uppercase, ≥1 lowercase, ≥1 special char.
func validatePassword(p string) error {
	if len(p) < minPasswordLen {
		return ErrWeakPassword
	}
	var hasUpper, hasLower, hasSpecial bool
	for _, r := range p {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsPunct(r) || unicode.IsSymbol(r):
			hasSpecial = true
		}
	}
	if !hasUpper || !hasLower || !hasSpecial {
		return ErrWeakPassword
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

// codeAlphabet is the character set for email verification codes.
// Uppercase letters + digits; ambiguous chars (0,1,I,O,L) removed.
const codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

// generateVerificationCode returns an 8-char uppercase alphanumeric code.
// 31^8 ≈ 852 billion combinations — brute force infeasible.
func generateVerificationCode() (string, error) {
	b := make([]byte, 8)
	alphabetLen := big.NewInt(int64(len(codeAlphabet)))
	for i := range b {
		n, err := rand.Int(rand.Reader, alphabetLen)
		if err != nil {
			return "", err
		}
		b[i] = codeAlphabet[n.Int64()]
	}
	return string(b), nil
}

// generateOTPCode returns a cryptographically-random 6-digit code (used for SMS OTP).
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
	raw   string       // 64-char hex — returned to the client, never stored
	token RefreshToken // stored in DB; token.TokenHash = SHA-256(raw)
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

// ── Email auth ────────────────────────────────────────────────────────────────

func (s *serviceImpl) Register(ctx context.Context, in RegisterInput) error {
	if err := validateEmail(in.Email); err != nil {
		return err
	}
	if err := validatePassword(in.Password); err != nil {
		return err
	}
	if err := validateLocale(in.Locale); err != nil {
		in.Locale = s.defaultLocale
	}

	emailHash, err := pkgcrypto.PhoneHash(in.Email) // same HMAC mechanism
	if err != nil {
		return fmt.Errorf("identity: hash email: %w", err)
	}
	if _, err := s.repo.FindUserByEmailHash(ctx, emailHash); err == nil {
		return ErrEmailAlreadyExists
	} else if !errors.Is(err, ErrUserNotFound) {
		return fmt.Errorf("identity: check email: %w", err)
	}

	emailEnc, err := pkgcrypto.EncryptPII(strings.ToLower(strings.TrimSpace(in.Email)))
	if err != nil {
		return fmt.Errorf("identity: encrypt email: %w", err)
	}
	pwHash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcryptPasswordCost)
	if err != nil {
		return fmt.Errorf("identity: hash password: %w", err)
	}

	name := strings.TrimSpace(in.NameFirst + " " + in.NameLast)
	user, err := s.repo.CreateEmailUser(ctx, emailHash, emailEnc, string(pwHash), name, in.Locale)
	if err != nil {
		return fmt.Errorf("identity: create user: %w", err)
	}

	return s.sendEmailVerification(ctx, user.ID, in.Email)
}

func (s *serviceImpl) LoginEmail(ctx context.Context, emailAddr, password, clientIP string) (LoginResult, error) {
	if err := validateEmail(emailAddr); err != nil {
		return LoginResult{}, ErrInvalidCredentials
	}
	emailHash, err := pkgcrypto.PhoneHash(strings.ToLower(strings.TrimSpace(emailAddr)))
	if err != nil {
		return LoginResult{}, fmt.Errorf("identity: hash email: %w", err)
	}

	user, err := s.repo.FindUserByEmailHash(ctx, emailHash)
	if errors.Is(err, ErrUserNotFound) {
		return LoginResult{}, ErrInvalidCredentials
	}
	if err != nil {
		return LoginResult{}, fmt.Errorf("identity: find user: %w", err)
	}
	if user.Status == StatusSuspended {
		return LoginResult{}, ErrUserSuspended
	}
	if user.Status == StatusDeleted {
		return LoginResult{}, ErrUserDeleted
	}
	if user.PasswordHash == "" {
		return LoginResult{}, ErrInvalidCredentials
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		if ferr := s.limiter.RecordVerifyFailure(ctx, emailHash); ferr != nil {
			return LoginResult{}, mapRatelimitErr(ferr)
		}
		return LoginResult{}, ErrInvalidCredentials
	}
	_ = s.limiter.ResetVerifyFailures(ctx, emailHash)

	if !user.EmailVerified {
		return LoginResult{}, ErrEmailNotVerified
	}

	if user.MFAEnabled {
		mfaPlain, err := pkgcrypto.DecryptPII(user.MFAPhoneEnc)
		if err != nil {
			return LoginResult{}, fmt.Errorf("identity: decrypt mfa phone: %w", err)
		}
		code, err := generateOTPCode()
		if err != nil {
			return LoginResult{}, err
		}
		codeHash, err := bcrypt.GenerateFromPassword([]byte(code), bcryptCost)
		if err != nil {
			return LoginResult{}, err
		}
		challengeRaw := generateOpaqueToken()
		challengeHash := hashToken(challengeRaw)

		if err := s.repo.CreateMFAChallenge(ctx, user.ID, challengeHash, string(codeHash),
			time.Now().Add(mfaChallengeTTL)); err != nil {
			return LoginResult{}, fmt.Errorf("identity: create mfa challenge: %w", err)
		}
		if err := s.sms.Send(ctx, mfaPlain, code); err != nil {
			s.log.Error("identity: mfa sms send", "err", err)
		}
		return LoginResult{
			MFAToken:    challengeRaw,
			MaskedPhone: MaskPhone(mfaPlain),
		}, nil
	}

	pair, err := s.issueTokensForUser(ctx, user.ID)
	if err != nil {
		return LoginResult{}, err
	}
	return LoginResult{Tokens: &pair}, nil
}

func (s *serviceImpl) VerifyEmail(ctx context.Context, emailAddr, code string) (TokenPair, error) {
	emailHash, err := pkgcrypto.PhoneHash(strings.ToLower(strings.TrimSpace(emailAddr)))
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: hash email: %w", err)
	}
	user, err := s.repo.FindUserByEmailHash(ctx, emailHash)
	if errors.Is(err, ErrUserNotFound) {
		return TokenPair{}, ErrEmailTokenInvalid
	}
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: find user: %w", err)
	}
	// Reject soft-deleted users BEFORE the already-verified short-circuit below
	// or any session issuance — otherwise a deleted email user could mint a fresh
	// session, bypassing deletion (mirrors LoginEmail). See CONTRIBUTING.
	if user.Status == StatusDeleted {
		return TokenPair{}, ErrUserDeleted
	}
	if user.EmailVerified {
		// Already verified — just issue a new session.
		return s.issueTokensForUser(ctx, user.ID)
	}
	v, err := s.repo.FindLatestEmailVerification(ctx, user.ID)
	if err != nil {
		return TokenPair{}, err
	}
	if time.Now().After(v.ExpiresAt) {
		return TokenPair{}, ErrEmailTokenExpired
	}
	// Case-insensitive: codes are stored uppercase, accept any casing from user.
	if err := bcrypt.CompareHashAndPassword([]byte(v.CodeHash), []byte(strings.ToUpper(code))); err != nil {
		return TokenPair{}, ErrEmailTokenInvalid
	}
	if err := s.repo.MarkEmailVerificationUsed(ctx, v.ID); err != nil {
		return TokenPair{}, err
	}
	if err := s.repo.MarkEmailVerified(ctx, user.ID); err != nil {
		return TokenPair{}, fmt.Errorf("identity: mark email verified: %w", err)
	}
	return s.issueTokensForUser(ctx, user.ID)
}

func (s *serviceImpl) ResendVerification(ctx context.Context, emailAddr string) error {
	emailHash, err := pkgcrypto.PhoneHash(strings.ToLower(strings.TrimSpace(emailAddr)))
	if err != nil {
		return nil // silent
	}
	user, err := s.repo.FindUserByEmailHash(ctx, emailHash)
	if err != nil {
		return nil // silent
	}
	if user.Status == StatusDeleted {
		return nil // silent — don't resend for deleted accounts; don't leak deleted status
	}
	if user.EmailVerified {
		return nil
	}
	emailPlain, err := pkgcrypto.DecryptPII(user.EmailEnc)
	if err != nil {
		return fmt.Errorf("identity: decrypt email: %w", err)
	}
	return s.sendEmailVerification(ctx, user.ID, emailPlain)
}

func (s *serviceImpl) ForgotPassword(ctx context.Context, emailAddr string) error {
	emailHash, err := pkgcrypto.PhoneHash(strings.ToLower(strings.TrimSpace(emailAddr)))
	if err != nil {
		return nil // silent
	}
	user, err := s.repo.FindUserByEmailHash(ctx, emailHash)
	if err != nil {
		return nil // silent — do not leak whether email exists
	}
	if user.Status == StatusDeleted {
		return nil // silent — no reset for deleted accounts; don't leak deleted status
	}
	token := generateOpaqueToken()
	tokenHash := hashToken(token)
	if err := s.repo.CreatePasswordReset(ctx, user.ID, tokenHash, time.Now().Add(passwordResetTTL)); err != nil {
		return fmt.Errorf("identity: create password reset: %w", err)
	}
	if err := s.emailProv.SendPasswordReset(ctx, emailAddr, token); err != nil {
		s.log.Error("identity: send password reset email", "err", err)
	}
	return nil
}

func (s *serviceImpl) ResetPassword(ctx context.Context, token, newPassword string) error {
	if err := validatePassword(newPassword); err != nil {
		return err
	}
	tokenHash := hashToken(token)
	reset, err := s.repo.FindPasswordReset(ctx, tokenHash)
	if err != nil {
		return err
	}
	if time.Now().After(reset.ExpiresAt) {
		return ErrPasswordResetExpired
	}
	if u, uerr := s.repo.GetUser(ctx, reset.UserID); uerr != nil {
		return uerr
	} else if u.Status == StatusDeleted {
		return ErrUserDeleted
	}
	pwHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcryptPasswordCost)
	if err != nil {
		return fmt.Errorf("identity: hash new password: %w", err)
	}
	if err := s.repo.SetPasswordHash(ctx, reset.UserID, string(pwHash)); err != nil {
		return fmt.Errorf("identity: set password: %w", err)
	}
	_ = s.repo.MarkPasswordResetUsed(ctx, reset.ID)
	_ = s.repo.RevokeAllUserTokens(ctx, reset.UserID)
	return nil
}

// ChangePassword rotates an authenticated user's password after verifying the
// current one. Mirrors ResetPassword's post-success behavior of revoking every
// active refresh token so the change propagates immediately to other devices.
func (s *serviceImpl) ChangePassword(ctx context.Context, userID int64, oldPassword, newPassword string) error {
	user, err := s.repo.GetUser(ctx, userID)
	if err != nil {
		return err
	}
	if user.Status == StatusDeleted {
		return ErrUserDeleted
	}
	if user.PasswordHash == "" {
		// Phone-only account — no password to rotate. Treat as invalid creds
		// (do not leak which kind of account this is).
		return ErrInvalidCredentials
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(oldPassword)); err != nil {
		return ErrInvalidCredentials
	}
	if err := validatePassword(newPassword); err != nil {
		return err
	}
	pwHash, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcryptPasswordCost)
	if err != nil {
		return fmt.Errorf("identity: hash new password: %w", err)
	}
	if err := s.repo.SetPasswordHash(ctx, userID, string(pwHash)); err != nil {
		return fmt.Errorf("identity: set password: %w", err)
	}
	_ = s.repo.RevokeAllUserTokens(ctx, userID)
	return nil
}

// ── MFA ───────────────────────────────────────────────────────────────────────

func (s *serviceImpl) EnrollMFA(ctx context.Context, userID int64, phone, clientIP string) error {
	if err := validatePhone(phone); err != nil {
		return err
	}
	user, err := s.repo.GetUser(ctx, userID)
	if err != nil {
		return err
	}
	if user.Status == StatusDeleted {
		return ErrUserDeleted
	}
	if user.MFAEnabled {
		return ErrMFAAlreadyEnabled
	}
	return s.RequestOTP(ctx, phone, OTPPurposeMFAEnroll, clientIP)
}

func (s *serviceImpl) ConfirmMFAEnroll(ctx context.Context, userID int64, phone, code string) error {
	if err := validatePhone(phone); err != nil {
		return err
	}
	phoneHash, err := pkgcrypto.PhoneHash(phone)
	if err != nil {
		return err
	}
	otp, err := s.repo.FindLatestOTP(ctx, phoneHash, OTPPurposeMFAEnroll)
	if errors.Is(err, ErrOTPNotFound) {
		return ErrMFACodeInvalid
	}
	if err != nil {
		return err
	}
	if time.Now().After(otp.ExpiresAt) {
		return ErrMFAChallengeExpired
	}
	if err := bcrypt.CompareHashAndPassword([]byte(otp.CodeHash), []byte(code)); err != nil {
		return ErrMFACodeInvalid
	}
	_ = s.repo.MarkOTPVerified(ctx, otp.ID)

	phoneEnc, err := pkgcrypto.EncryptPII(phone)
	if err != nil {
		return fmt.Errorf("identity: encrypt mfa phone: %w", err)
	}
	return s.repo.UpdateMFAConfig(ctx, userID, true, phoneHash, phoneEnc)
}

// VerifyMFAChallenge has no inline StatusDeleted guard by design: an MFA
// challenge can only be created by LoginEmail (service.go ~518), which already
// rejects soft-deleted users before issuing the challenge. A deleted user can
// therefore never hold a valid challenge token to reach this path. See the
// user-state-consumer discipline section in CONTRIBUTING.md.
func (s *serviceImpl) VerifyMFAChallenge(ctx context.Context, challengeToken, code string) (TokenPair, error) {
	challengeHash := hashToken(challengeToken)
	challenge, err := s.repo.FindMFAChallenge(ctx, challengeHash)
	if err != nil {
		return TokenPair{}, err
	}
	if time.Now().After(challenge.ExpiresAt) {
		return TokenPair{}, ErrMFAChallengeExpired
	}
	if err := bcrypt.CompareHashAndPassword([]byte(challenge.CodeHash), []byte(code)); err != nil {
		return TokenPair{}, ErrMFACodeInvalid
	}
	_ = s.repo.MarkMFAChallengeVerified(ctx, challenge.ID)
	return s.issueTokensForUser(ctx, challenge.UserID)
}

func (s *serviceImpl) DisableMFA(ctx context.Context, userID int64) error {
	return s.repo.UpdateMFAConfig(ctx, userID, false, nil, "")
}

// ── Shared helpers ────────────────────────────────────────────────────────────

func (s *serviceImpl) issueTokensForUser(ctx context.Context, userID int64) (TokenPair, error) {
	rtc := newRefreshTokenCreation()
	if err := s.repo.CreateSession(ctx, userID, rtc.token); err != nil {
		return TokenPair{}, fmt.Errorf("identity: create session: %w", err)
	}
	accessToken, _, err := s.signer.IssueAccess(userID, s.market)
	if err != nil {
		return TokenPair{}, fmt.Errorf("identity: issue access token: %w", err)
	}
	return TokenPair{
		AccessToken:      accessToken,
		RefreshToken:     rtc.raw,
		RefreshExpiresAt: rtc.token.ExpiresAt,
	}, nil
}

func (s *serviceImpl) sendEmailVerification(ctx context.Context, userID int64, emailAddr string) error {
	code, err := generateVerificationCode()
	if err != nil {
		return err
	}
	// Store and compare uppercase to allow case-insensitive user input.
	code = strings.ToUpper(code)
	codeHash, err := bcrypt.GenerateFromPassword([]byte(code), bcryptCost)
	if err != nil {
		return err
	}
	if err := s.repo.CreateEmailVerification(ctx, userID, string(codeHash), time.Now().Add(emailVerifyTTL)); err != nil {
		return fmt.Errorf("identity: store verification: %w", err)
	}
	if err := s.emailProv.SendVerification(ctx, emailAddr, code); err != nil {
		s.log.Error("identity: send verification email", "err", err)
	}
	return nil
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

// ── Address methods ───────────────────────────────────────────────────────────

var e164Regexp = regexp.MustCompile(`^\+[0-9]{7,15}$`)

func (s *serviceImpl) ListAddresses(ctx context.Context, userID int64) ([]Address, error) {
	addrs, err := s.repo.ListAddresses(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("identity: list addresses: %w", err)
	}
	result := make([]Address, 0, len(addrs))
	for _, a := range addrs {
		dec, dErr := decryptAddress(a)
		if dErr != nil {
			s.log.Error("identity: decrypt address", "address_id", a.ID, "err", dErr)
			continue
		}
		result = append(result, dec)
	}
	return result, nil
}

func (s *serviceImpl) CreateAddress(ctx context.Context, userID int64, in AddressInput) (Address, error) {
	if in.Phone != "" && !e164Regexp.MatchString(in.Phone) {
		return Address{}, ErrAddressInvalidPhone
	}
	row, err := encryptAddressInput(in)
	if err != nil {
		return Address{}, fmt.Errorf("identity: encrypt address: %w", err)
	}
	if in.IsDefault {
		if err := s.repo.ClearDefaultAddresses(ctx, userID); err != nil {
			return Address{}, fmt.Errorf("identity: clear defaults: %w", err)
		}
	}
	created, err := s.repo.InsertAddress(ctx, userID, row)
	if err != nil {
		return Address{}, fmt.Errorf("identity: insert address: %w", err)
	}
	return decryptAddress(created)
}

func (s *serviceImpl) GetAddress(ctx context.Context, userID, addressID int64) (Address, error) {
	a, err := s.repo.GetAddress(ctx, userID, addressID)
	if err != nil {
		return Address{}, err
	}
	return decryptAddress(a)
}

func (s *serviceImpl) UpdateAddress(ctx context.Context, userID, addressID int64, in AddressInput) (Address, error) {
	if in.Phone != "" && !e164Regexp.MatchString(in.Phone) {
		return Address{}, ErrAddressInvalidPhone
	}
	row, err := encryptAddressInput(in)
	if err != nil {
		return Address{}, fmt.Errorf("identity: encrypt address: %w", err)
	}
	if in.IsDefault {
		if err := s.repo.ClearDefaultAddresses(ctx, userID); err != nil {
			return Address{}, fmt.Errorf("identity: clear defaults: %w", err)
		}
	}
	updated, err := s.repo.UpdateAddress(ctx, userID, addressID, row)
	if err != nil {
		return Address{}, err
	}
	return decryptAddress(updated)
}

func (s *serviceImpl) DeleteAddress(ctx context.Context, userID, addressID int64) error {
	return s.repo.DeleteAddress(ctx, userID, addressID)
}

// encryptAddressInput encrypts PII fields from AddressInput into an AddressRow.
func encryptAddressInput(in AddressInput) (AddressRow, error) {
	nameEnc, err := pkgcrypto.EncryptPII(in.Name)
	if err != nil {
		return AddressRow{}, err
	}
	phoneEnc, err := pkgcrypto.EncryptPII(in.Phone)
	if err != nil {
		return AddressRow{}, err
	}
	fullAddrEnc, err := pkgcrypto.EncryptPII(in.FullAddress)
	if err != nil {
		return AddressRow{}, err
	}
	neighEnc, err := pkgcrypto.EncryptPII(in.Neighborhood)
	if err != nil {
		return AddressRow{}, err
	}
	return AddressRow{
		Label:           in.Label,
		NameEnc:         nameEnc,
		PhoneEnc:        phoneEnc,
		FullAddressEnc:  fullAddrEnc,
		NeighborhoodEnc: neighEnc,
		District:        in.District,
		City:            in.City,
		PostalCode:      in.PostalCode,
		IsDefault:       in.IsDefault,
	}, nil
}

// decryptAddress decrypts PII fields of a stored address back to plaintext.
// The stored address has encrypted strings in the PII fields; after decryption
// they are copied into the display fields.
func decryptAddress(a Address) (Address, error) {
	name, err := pkgcrypto.DecryptPII(a.Name)
	if err != nil {
		return Address{}, fmt.Errorf("identity: decrypt name: %w", err)
	}
	phone, err := pkgcrypto.DecryptPII(a.Phone)
	if err != nil {
		return Address{}, fmt.Errorf("identity: decrypt phone: %w", err)
	}
	fullAddr, err := pkgcrypto.DecryptPII(a.FullAddress)
	if err != nil {
		return Address{}, fmt.Errorf("identity: decrypt full_address: %w", err)
	}
	var neigh string
	if a.Neighborhood != "" {
		neigh, err = pkgcrypto.DecryptPII(a.Neighborhood)
		if err != nil {
			return Address{}, fmt.Errorf("identity: decrypt neighborhood: %w", err)
		}
	}
	a.Name = name
	a.Phone = phone
	a.FullAddress = fullAddr
	a.Neighborhood = neigh
	return a, nil
}
