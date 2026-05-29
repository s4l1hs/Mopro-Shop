// Package identity manages user authentication, OTP verification, JWT issuance, and device registration.
package identity

import (
	"context"
	"time"
)

// Service is the public interface of the identity module.
// All callers (HTTP handlers) use only this interface — never the struct directly.
type Service interface {
	// RequestOTP generates a 6-digit OTP and sends it via SMS to the phone number.
	// purpose must be OTPPurposeLogin or OTPPurposeStepUp.
	RequestOTP(ctx context.Context, phoneE164 string, purpose string, clientIP string) error

	// VerifyOTP validates the OTP code and, on success, returns an access + refresh token pair.
	// For step-up purpose, returns only the step-up token inside TokenPair.AccessToken.
	VerifyOTP(ctx context.Context, phoneE164 string, purpose string, code string) (TokenPair, error)

	// RefreshTokens rotates the refresh token and returns a new access + refresh pair.
	// Token reuse (presenting an already-rotated token) revokes the entire token family.
	RefreshTokens(ctx context.Context, refreshToken string) (TokenPair, error)

	// Logout revokes the given refresh token immediately.
	Logout(ctx context.Context, refreshToken string) error

	// GetMe returns the authenticated user's profile.
	GetMe(ctx context.Context, userID int64) (User, error)

	// UpdateMe applies a partial update to the authenticated user's profile.
	UpdateMe(ctx context.Context, userID int64, updates UserUpdates) (User, error)

	// DeleteMe soft-deletes the account and revokes all sessions.
	DeleteMe(ctx context.Context, userID int64) error

	// RequestStepUpOTP sends a step-up OTP to the user's registered phone.
	RequestStepUpOTP(ctx context.Context, userID int64, clientIP string) error

	// VerifyStepUpOTP validates the step-up code and returns a short-lived step-up JWT.
	VerifyStepUpOTP(ctx context.Context, userID int64, code string) (StepUpToken, error)

	// RegisterDevice records an FCM token for push-notification delivery.
	RegisterDevice(ctx context.Context, userID int64, info DeviceInfo) (Device, error)

	// ListAddresses returns all saved addresses for the user (caller-owned only).
	ListAddresses(ctx context.Context, userID int64) ([]Address, error)

	// CreateAddress creates and returns a new delivery address for the user.
	// If IsDefault is true, all other addresses for the user are unset as default.
	CreateAddress(ctx context.Context, userID int64, in AddressInput) (Address, error)

	// GetAddress returns a single address.
	// Returns ErrAddressNotFound when the address doesn't exist or belongs to another user.
	GetAddress(ctx context.Context, userID, addressID int64) (Address, error)

	// UpdateAddress replaces all fields of the address.
	// Returns ErrAddressNotFound when the address doesn't exist or belongs to another user.
	UpdateAddress(ctx context.Context, userID, addressID int64, in AddressInput) (Address, error)

	// DeleteAddress permanently removes the address.
	// Returns ErrAddressNotFound when the address doesn't exist or belongs to another user.
	DeleteAddress(ctx context.Context, userID, addressID int64) error

	// ── Email auth ────────────────────────────────────────────────────────────

	// Register creates a new email+password account and sends a verification email.
	Register(ctx context.Context, in RegisterInput) error

	// LoginEmail authenticates with email and password.
	// Returns LoginResult.Tokens when MFA is not required.
	// Returns LoginResult.MFAToken when MFA is enabled (client must call VerifyMFAChallenge).
	LoginEmail(ctx context.Context, email, password, clientIP string) (LoginResult, error)

	// VerifyEmail confirms the 6-digit code for the given email address.
	// On success the user's email_verified flag is set and a full token pair is returned.
	// This is a public endpoint — the user has no access token yet at this stage.
	VerifyEmail(ctx context.Context, email, code string) (TokenPair, error)

	// ResendVerification sends a new verification email for the given email address (public).
	ResendVerification(ctx context.Context, email string) error

	// ForgotPassword sends a password-reset email. Silently no-ops if email is not found.
	ForgotPassword(ctx context.Context, email string) error

	// ResetPassword applies a new password using a reset token.
	// On success all existing refresh tokens are revoked (force logout everywhere).
	ResetPassword(ctx context.Context, token, newPassword string) error

	// ChangePassword rotates the password for an authenticated user. The
	// caller MUST present `oldPassword` for verification. Returns
	// ErrInvalidCredentials if the old password is wrong, ErrWeakPassword if
	// the new one fails strength rules, ErrUserNotFound if the user record
	// is gone. On success all other refresh tokens are revoked.
	ChangePassword(ctx context.Context, userID int64, oldPassword, newPassword string) error

	// ── MFA ───────────────────────────────────────────────────────────────────

	// EnrollMFA sends an OTP to phone for MFA setup. User must confirm with ConfirmMFAEnroll.
	EnrollMFA(ctx context.Context, userID int64, phone, clientIP string) error

	// ConfirmMFAEnroll verifies the OTP and enables MFA on the account.
	ConfirmMFAEnroll(ctx context.Context, userID int64, phone, code string) error

	// VerifyMFAChallenge validates the MFA OTP and issues a token pair.
	VerifyMFAChallenge(ctx context.Context, challengeToken, code string) (TokenPair, error)

	// DisableMFA disables MFA for the user. The caller must have step-up auth.
	DisableMFA(ctx context.Context, userID int64) error
}

// Repository is the storage interface of the identity module.
// Implementations are in repository.go (pgx).
type Repository interface {
	// FindUserByPhoneHash returns the user matching the given HMAC-SHA256 phone hash.
	FindUserByPhoneHash(ctx context.Context, phoneHash []byte) (User, error)

	// FindLatestOTP returns the most recent unverified OTP for (phoneHash, purpose).
	FindLatestOTP(ctx context.Context, phoneHash []byte, purpose string) (OTP, error)

	// MarkOTPVerifiedAndCreateSession atomically:
	//   1. marks otp_codes.verified_at = now() for otpID
	//   2. upserts the user row (insert on first login, select on subsequent)
	//   3. inserts a new refresh_token row
	// Returns the resolved user and nil on success.
	MarkOTPVerifiedAndCreateSession(
		ctx context.Context,
		otpID int64,
		phoneHash []byte,
		phoneEnc string,
		market string,
		defaultLocale string,
		newToken RefreshToken,
	) (User, error)

	// CreateOTP inserts a new OTP record.
	CreateOTP(ctx context.Context, otp OTP) error

	// MarkOTPVerified marks a single OTP as used (verified_at = now()).
	// Returns ErrOTPAlreadyUsed if the OTP was already verified.
	MarkOTPVerified(ctx context.Context, otpID int64) error

	// FindTokenByHash returns the refresh token record for the given SHA-256 hex hash.
	FindTokenByHash(ctx context.Context, tokenHash string) (RefreshToken, error)

	// RotateRefreshToken atomically:
	//   1. revokes the current token (reason="rotation")
	//   2. inserts a replacement token with the same family_root
	// If the current token is already revoked (theft), RevokeTokenFamily is called first.
	// Returns the new token and the owning user on success.
	RotateRefreshToken(ctx context.Context, currentTokenHash string, newToken RefreshToken) (User, RefreshToken, error)

	// RevokeToken marks a single token as revoked (reason="logout").
	RevokeToken(ctx context.Context, tokenHash string) error

	// RevokeTokenFamily revokes all active tokens sharing the same family_root.
	RevokeTokenFamily(ctx context.Context, familyRoot string) error

	// GetUser returns a user by primary key.
	GetUser(ctx context.Context, id int64) (User, error)

	// UpdateUser applies non-nil fields from UserUpdates to the user row and returns the updated user.
	UpdateUser(ctx context.Context, id int64, updates UserUpdates) (User, error)

	// SoftDeleteWithRevoke atomically sets user status='deleted', deleted_at=now()
	// and revokes all active refresh tokens for that user.
	SoftDeleteWithRevoke(ctx context.Context, userID int64) error

	// CreateDevice inserts a device record.
	// If the same FCM token already exists and is active, the old record is revoked first.
	CreateDevice(ctx context.Context, userID int64, info DeviceInfo) (Device, error)

	// ListAddresses returns all addresses for the given user.
	ListAddresses(ctx context.Context, userID int64) ([]Address, error)

	// InsertAddress inserts a new address row and returns it with its generated ID.
	// If isDefault is true, the caller must have already cleared other defaults in the same tx.
	InsertAddress(ctx context.Context, userID int64, a AddressRow) (Address, error)

	// ClearDefaultAddresses sets is_default=false for all addresses of the user.
	ClearDefaultAddresses(ctx context.Context, userID int64) error

	// GetAddress returns the address with the given id, only if it belongs to userID.
	GetAddress(ctx context.Context, userID, addressID int64) (Address, error)

	// UpdateAddress replaces all mutable address fields.
	UpdateAddress(ctx context.Context, userID, addressID int64, a AddressRow) (Address, error)

	// DeleteAddress hard-deletes the address.
	DeleteAddress(ctx context.Context, userID, addressID int64) error

	// ── Email auth ────────────────────────────────────────────────────────────

	FindUserByEmailHash(ctx context.Context, emailHash []byte) (User, error)
	CreateEmailUser(ctx context.Context, emailHash []byte, emailEnc, passwordHash, name, locale string) (User, error)
	SetPasswordHash(ctx context.Context, userID int64, passwordHash string) error
	MarkEmailVerified(ctx context.Context, userID int64) error

	CreateEmailVerification(ctx context.Context, userID int64, codeHash string, expiresAt time.Time) error
	FindLatestEmailVerification(ctx context.Context, userID int64) (EmailVerification, error)
	MarkEmailVerificationUsed(ctx context.Context, id int64) error

	CreatePasswordReset(ctx context.Context, userID int64, tokenHash string, expiresAt time.Time) error
	FindPasswordReset(ctx context.Context, tokenHash string) (PasswordReset, error)
	MarkPasswordResetUsed(ctx context.Context, id int64) error

	// CreateSession inserts a refresh token for an existing user.
	// Used for email login (unlike MarkOTPVerifiedAndCreateSession which also upserts the user).
	CreateSession(ctx context.Context, userID int64, token RefreshToken) error

	// RevokeAllUserTokens revokes every active refresh token belonging to userID.
	RevokeAllUserTokens(ctx context.Context, userID int64) error

	// ── MFA ───────────────────────────────────────────────────────────────────

	UpdateMFAConfig(ctx context.Context, userID int64, enabled bool, phoneHash []byte, phoneEnc string) error
	CreateMFAChallenge(ctx context.Context, userID int64, challengeHash, codeHash string, expiresAt time.Time) error
	FindMFAChallenge(ctx context.Context, challengeHash string) (MFAChallenge, error)
	MarkMFAChallengeVerified(ctx context.Context, id int64) error
}
