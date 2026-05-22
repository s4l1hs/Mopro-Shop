// Package identity manages user authentication, OTP verification, JWT issuance, and device registration.
package identity

import "context"

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
}
