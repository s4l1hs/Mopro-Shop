// Package logger provides a market-aware structured logger wrapping log/slog.
package logger

import (
	"context"
	"log/slog"
	"os"
)

// New returns a JSON slog.Logger pre-seeded with service and market labels.
func New(service, market string) *slog.Logger {
	return slog.New(slog.NewJSONHandler(os.Stdout, nil)).With(
		slog.String("service", service),
		slog.String("market", market),
	)
}

// FromContext extracts a logger from context, falling back to a default logger.
// TODO(mopro:placeholder): store and retrieve logger in context (Phase 1)
func FromContext(_ context.Context) *slog.Logger {
	return slog.Default()
}
