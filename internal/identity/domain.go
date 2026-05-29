package identity

import (
	"strings"
	"time"
	"unicode/utf8"
)

// User is the canonical domain representation of a registered user.
type User struct {
	ID            int64
	PhoneHash     []byte // HMAC-SHA256 of E.164 phone (legacy OTP login)
	PhoneEnc      string // AES-GCM encrypted E.164 phone
	EmailHash     []byte // HMAC-SHA256 of email — indexed lookup for email auth
	EmailEnc      string // AES-GCM encrypted email
	PasswordHash  string // bcrypt(cost=12) of plaintext password; empty for phone-only users
	EmailVerified bool   // true after the user clicks the verification link/code
	MFAEnabled    bool   // true when phone-based MFA is active
	MFAPhoneHash  []byte // HMAC-SHA256 of MFA phone
	MFAPhoneEnc   string // AES-GCM encrypted MFA phone
	Name          string // full display name (not encrypted)
	Locale        string // BCP 47, e.g. "tr-TR"
	Status        string // "active" | "suspended" | "deleted"
	CreatedAt     time.Time
	UpdatedAt     time.Time
	DeletedAt     *time.Time
}

// EmailVerification is a short-lived code sent to a user's email.
type EmailVerification struct {
	ID        int64
	UserID    int64
	CodeHash  string // bcrypt of 6-digit code
	ExpiresAt time.Time
	UsedAt    *time.Time
	CreatedAt time.Time
}

// PasswordReset is a short-lived opaque token sent by email for password recovery.
type PasswordReset struct {
	ID        int64
	UserID    int64
	TokenHash string // SHA-256 hex of the opaque token
	ExpiresAt time.Time
	UsedAt    *time.Time
	CreatedAt time.Time
}

// MFAChallenge is an in-flight MFA step created when the user logs in with MFA enabled.
type MFAChallenge struct {
	ID            int64
	UserID        int64
	ChallengeHash string // SHA-256 hex of the opaque challenge token given to the client
	CodeHash      string // bcrypt of OTP sent to MFA phone
	ExpiresAt     time.Time
	VerifiedAt    *time.Time
	CreatedAt     time.Time
}

// LoginResult is the return value of LoginEmail.
// Exactly one branch is populated.
type LoginResult struct {
	Tokens      *TokenPair // non-nil when authentication succeeded with no MFA
	MFAToken    string     // non-empty when MFA is required; client sends this back to /auth/mfa/verify
	MaskedPhone string     // display-only masked phone when MFA is required
}

// RegisterInput carries the fields required to create a new email-based account.
type RegisterInput struct {
	Email     string
	Password  string
	NameFirst string
	NameLast  string
	Locale    string
}

const (
	OTPPurposeMFAEnroll = "mfa_enroll"

	emailVerifyTTL     = 15 * time.Minute
	passwordResetTTL   = 1 * time.Hour
	mfaChallengeTTL    = 5 * time.Minute
	bcryptPasswordCost = 12 // permanent credential — higher cost than OTP hashes
	minPasswordLen     = 8
)

// OTP is a one-time password code record.
type OTP struct {
	ID         int64
	PhoneHash  []byte
	Purpose    string // "login" | "step_up"
	CodeHash   string // bcrypt(cost=10) of 6-digit plaintext code
	CreatedAt  time.Time
	ExpiresAt  time.Time
	VerifiedAt *time.Time
}

// RefreshToken is an opaque rotation-capable session token.
type RefreshToken struct {
	ID            int64
	UserID        int64
	TokenHash     string // hex(SHA-256(64-char random token))
	FamilyRoot    string // shared across all rotations in the same chain; used for family revocation
	IssuedAt      time.Time
	ExpiresAt     time.Time
	RevokedAt     *time.Time
	RevokedReason string // "rotation" | "logout" | "theft" | "admin" | "expired"
}

// Device is a registered FCM push-notification endpoint.
type Device struct {
	ID           int64
	UserID       int64
	FCMToken     string
	DeviceModel  string
	OSVersion    string
	RegisteredAt time.Time
	RevokedAt    *time.Time
}

// DeviceInfo carries client-provided fields when registering a device.
type DeviceInfo struct {
	FCMToken    string
	DeviceModel string
	OSVersion   string
}

// TokenPair is returned after a successful OTP verification.
type TokenPair struct {
	AccessToken      string
	RefreshToken     string
	RefreshExpiresAt time.Time
}

// StepUpToken is returned after a successful step-up OTP verification.
type StepUpToken struct {
	Token     string
	ExpiresAt time.Time
}

// UserUpdates carries mutable fields for PATCH /me.
// Only non-nil fields are applied.
type UserUpdates struct {
	Name   *string
	Email  *string // raw plaintext; caller must encrypt before storing
	Locale *string
}

// OTPPurpose constants.
const (
	OTPPurposeLogin  = "login"
	OTPPurposeStepUp = "step_up"
)

// Status constants.
const (
	StatusActive    = "active"
	StatusSuspended = "suspended"
	StatusDeleted   = "deleted"
)

// Address is a user's saved delivery address.
// PII fields (Name, Phone, FullAddress, Neighborhood) are stored AES-GCM encrypted;
// District, City, PostalCode are stored plaintext for logistics routing.
type Address struct {
	ID           int64     `json:"id"`
	UserID       int64     `json:"user_id"`
	Label        string    `json:"label"`
	Name         string    `json:"name"`         // decrypted display name
	Phone        string    `json:"phone"`        // decrypted E.164 phone
	FullAddress  string    `json:"full_address"` // decrypted street address line
	Neighborhood string    `json:"neighborhood"` // decrypted neighborhood; empty when absent
	District     string    `json:"district"`
	City         string    `json:"city"`
	PostalCode   string    `json:"postal_code"`
	IsDefault    bool      `json:"is_default"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// AddressInput carries mutable fields for create/update address.
// Phone is optional; when present it must be a valid E.164 number.
type AddressInput struct {
	Label        string `json:"label"`
	Name         string `json:"name"`
	Phone        string `json:"phone"` // optional; validated when non-empty
	FullAddress  string `json:"full_address"`
	Neighborhood string `json:"neighborhood"` // optional
	District     string `json:"district"`
	City         string `json:"city"`
	PostalCode   string `json:"postal_code"` // optional
	IsDefault    bool   `json:"is_default"`
}

// AddressRow is the encrypted storage representation passed from service to repo.
type AddressRow struct {
	Label           string
	NameEnc         string
	PhoneEnc        string
	FullAddressEnc  string
	NeighborhoodEnc string // empty string when absent
	District        string
	City            string
	PostalCode      string
	IsDefault       bool
}

// MaskPhone masks an E.164 phone number for display.
// "+905321234567" → "+90 5XX XXX XX 67"
// For numbers shorter than expected, falls back to showing last 2 digits only.
func MaskPhone(e164 string) string {
	if !strings.HasPrefix(e164, "+") {
		return "***"
	}
	r := []rune(e164)
	n := utf8.RuneCountInString(e164)
	if n < 4 {
		return "***"
	}
	// TR format: +90 5XX XXX XX 67 (13 chars total for TR numbers)
	if n == 13 && strings.HasPrefix(e164, "+90") {
		// r[0..2] = "+90", r[3] = operator prefix digit, r[11..12] = last 2
		return "+90 " + string(r[3]) + "XX XXX XX " + string(r[11:13])
	}
	// Generic fallback: country code + *** + last 2 digits
	last2 := string(r[n-2:])
	return e164[:3] + "***" + last2
}
