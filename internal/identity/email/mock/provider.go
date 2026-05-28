// Package mock provides a no-op email provider that logs outgoing messages.
// Used when EMAIL_PROVIDER=mock (default in development).
package mock

import (
	"context"
	"log/slog"
	"strings"
	"sync"
)

// Provider is the exported type so callers can access LastCode for dev endpoints.
type Provider struct {
	log   *slog.Logger
	mu    sync.RWMutex
	codes map[string]string // email (lowercase) → last verification code
}

// New returns a mock email provider.
func New(log *slog.Logger) *Provider {
	if log == nil {
		log = slog.Default()
	}
	return &Provider{log: log, codes: make(map[string]string)}
}

func (p *Provider) SendVerification(_ context.Context, toEmail, code string) error {
	p.log.Info("mock email: verification code", "to", toEmail, "code", code)
	p.mu.Lock()
	p.codes[strings.ToLower(toEmail)] = code
	p.mu.Unlock()
	return nil
}

func (p *Provider) SendPasswordReset(_ context.Context, toEmail, resetToken string) error {
	p.log.Info("mock email: password reset token", "to", toEmail, "reset_token", resetToken)
	return nil
}

// LastVerificationCode returns the last code sent to the given email.
// Returns "" if no code has been sent. Only call this in dev mode.
func (p *Provider) LastVerificationCode(email string) string {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return p.codes[strings.ToLower(email)]
}
