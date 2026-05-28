// Package email defines the provider interface for transactional emails.
// Active provider is selected by EMAIL_PROVIDER env var: "mock" (default) | "smtp".
package email

import "context"

// Provider sends transactional emails on behalf of the identity module.
type Provider interface {
	// SendVerification sends a 6-digit verification code to the given address.
	SendVerification(ctx context.Context, toEmail, code string) error

	// SendPasswordReset sends a password-reset link containing resetToken.
	SendPasswordReset(ctx context.Context, toEmail, resetToken string) error
}
