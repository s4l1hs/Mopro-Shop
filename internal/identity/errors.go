package identity

import "errors"

// ── OTP errors ───────────────────────────────────────────────────────────────

var (
	ErrOTPNotFound    = errors.New("identity: OTP not found")
	ErrOTPExpired     = errors.New("identity: OTP expired")
	ErrOTPAlreadyUsed = errors.New("identity: OTP already verified")
	ErrOTPInvalid     = errors.New("identity: OTP code does not match")
)

// ── Rate-limit errors ─────────────────────────────────────────────────────────

var (
	// ErrOTPRateLimitExceeded is returned when OTP request rate limits are exceeded
	// (3 per 10 min or 5 per hour for the phone, 10 per hour for the IP).
	ErrOTPRateLimitExceeded = errors.New("identity: OTP request rate limit exceeded")
	// ErrOTPVerifyLocked is returned when 10 failed verify attempts lock the phone for 1 hour.
	ErrOTPVerifyLocked = errors.New("identity: phone locked due to too many failed OTP attempts")
)

// ── Token errors ──────────────────────────────────────────────────────────────

var (
	ErrTokenNotFound = errors.New("identity: refresh token not found")
	ErrTokenExpired  = errors.New("identity: refresh token expired")
	ErrTokenRevoked  = errors.New("identity: refresh token revoked")
	// ErrTokenFamilyRevoked is returned when a revoked token from the same rotation family
	// is presented — indicates potential token theft; the entire family is revoked.
	ErrTokenFamilyRevoked = errors.New("identity: refresh token family revoked (theft detected)")
	ErrStepUpTokenInvalid = errors.New("identity: step-up token invalid or expired")
)

// ── User errors ───────────────────────────────────────────────────────────────

var (
	ErrUserNotFound  = errors.New("identity: user not found")
	ErrUserSuspended = errors.New("identity: user account suspended")
	ErrUserDeleted   = errors.New("identity: user account deleted")
)

// ── Device errors ─────────────────────────────────────────────────────────────

var (
	ErrDeviceNotFound = errors.New("identity: device not found")
)

// ── SMS errors ────────────────────────────────────────────────────────────────

var (
	ErrSMSSendFailed          = errors.New("identity: SMS send failed")
	ErrSMSInsufficientBalance = errors.New("identity: SMS provider insufficient balance")
)

// ── Crypto / input errors ─────────────────────────────────────────────────────

var (
	ErrInvalidPhone  = errors.New("identity: phone must be E.164 format (+XXXXXXXXXXX)")
	ErrInvalidEmail  = errors.New("identity: invalid email format")
	ErrInvalidLocale = errors.New("identity: unsupported locale")
)

// ── Address errors ────────────────────────────────────────────────────────────

var (
	ErrAddressNotFound     = errors.New("identity: address not found")
	ErrAddressInvalidPhone = errors.New("identity: address phone must be E.164 format")
)
