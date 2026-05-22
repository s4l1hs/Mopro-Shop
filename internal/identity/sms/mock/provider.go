// Package mock provides a no-op SMS provider that logs the OTP code.
// Used when SMS_PROVIDER=mock (default in development and test environments).
package mock

import (
	"context"
	"log/slog"
)

// Provider logs the OTP at INFO level instead of sending a real SMS.
// NEVER use in production — the code appears in plain text in logs.
type Provider struct {
	log *slog.Logger
}

// New returns a mock SMS provider that logs OTP codes.
func New(log *slog.Logger) *Provider {
	return &Provider{log: log}
}

func (p *Provider) Send(_ context.Context, toE164 string, code string) error {
	p.log.Info("mock SMS: OTP code", "to", toE164, "code", code)
	return nil
}
