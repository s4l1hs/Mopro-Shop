package identity

import (
	"strings"
	"time"
	"unicode/utf8"
)

// User is the canonical domain representation of a registered user.
type User struct {
	ID        int64
	PhoneHash []byte // HMAC-SHA256 of E.164 phone — stored in DB for indexed lookup
	PhoneEnc  string // AES-GCM encrypted E.164 phone — stored in DB, decrypted for display
	EmailEnc  string // AES-GCM encrypted email — empty string when absent
	Name      string // full display name (not encrypted)
	Locale    string // BCP 47, e.g. "tr-TR"
	Status    string // "active" | "suspended" | "deleted"
	CreatedAt time.Time
	UpdatedAt time.Time
	DeletedAt *time.Time
}

// OTP is a one-time password code record.
type OTP struct {
	ID          int64
	PhoneHash   []byte
	Purpose     string // "login" | "step_up"
	CodeHash    string // bcrypt(cost=10) of 6-digit plaintext code
	CreatedAt   time.Time
	ExpiresAt   time.Time
	VerifiedAt  *time.Time
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

// UserUpdates carries mutable fields for PATCH /v1/me.
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
	ID           int64
	UserID       int64
	Label        string
	Name         string // decrypted display name
	Phone        string // decrypted E.164 phone
	FullAddress  string // decrypted street address line
	Neighborhood string // decrypted neighborhood; empty when absent
	District     string
	City         string
	PostalCode   string
	IsDefault    bool
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// AddressInput carries mutable fields for create/update address.
// Phone is optional; when present it must be a valid E.164 number.
type AddressInput struct {
	Label        string
	Name         string
	Phone        string // optional; validated when non-empty
	FullAddress  string
	Neighborhood string // optional
	District     string
	City         string
	PostalCode   string // optional
	IsDefault    bool
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
