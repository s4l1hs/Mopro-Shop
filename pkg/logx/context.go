package logx

import (
	"context"
	"log/slog"
)

type ctxKey struct{}

// Inject stores l in ctx and returns the new context.
func Inject(ctx context.Context, l *slog.Logger) context.Context {
	return context.WithValue(ctx, ctxKey{}, l)
}

// From returns the logger stored in ctx.
// Falls back to slog.Default() when none is present.
func From(ctx context.Context) *slog.Logger {
	if l, ok := ctx.Value(ctxKey{}).(*slog.Logger); ok && l != nil {
		return l
	}
	return slog.Default()
}

// With adds key-value pairs to the logger in ctx and returns a new ctx with
// the enriched logger injected.
func With(ctx context.Context, args ...any) context.Context {
	return Inject(ctx, From(ctx).With(args...))
}
