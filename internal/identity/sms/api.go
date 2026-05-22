// Package sms defines the SMS provider interface for OTP delivery.
// Active provider is selected by SMS_PROVIDER env var: "mock" (default) | "netgsm" | "iletimerkezi".
package sms

import "context"

// Provider delivers OTP codes via SMS.
type Provider interface {
	// Send sends a single OTP SMS to the given E.164 phone number.
	// Returns ErrInsufficientBalance when the account credit is exhausted.
	Send(ctx context.Context, toE164 string, code string) error
}
