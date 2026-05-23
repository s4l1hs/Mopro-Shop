// Package httpx provides shared HTTP middleware: TraceAndLog, Idempotency, and Locale.
package httpx

import (
	"net/http"

	"github.com/mopro/platform/pkg/otelx"
)

// Handler is an alias for the standard HTTP handler function.
type Handler = http.HandlerFunc

// TraceAndLog wraps next with the full observability chain:
// panic recovery, W3C trace context propagation, OTel span, and structured request logging.
// Delegates to pkg/otelx.TraceAndLog.
func TraceAndLog(next http.Handler) http.Handler {
	return otelx.TraceAndLog(next)
}

// Idempotency validates the Idempotency-Key header required on all POST/PUT endpoints.
// TODO(mopro:placeholder): implement idempotency key validation and deduplication
func Idempotency(next http.Handler) http.Handler {
	return next
}

// Locale extracts locale from Accept-Language / user profile and stores it in context.
// TODO(mopro:placeholder): implement locale extraction and context injection
func Locale(next http.Handler) http.Handler {
	return next
}
