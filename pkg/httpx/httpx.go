// Package httpx provides shared HTTP middleware: TraceAndLog, Idempotency, and Locale.
package httpx

import "net/http"

// Handler is an alias for the standard HTTP handler function.
type Handler = http.HandlerFunc

// TraceAndLog injects trace_id/span_id into context and logs the request.
// TODO(mopro:placeholder): implement OTel trace propagation and structured request logging
// Unblocked by: Phase 1 (OTel setup via pkg/tracing)
func TraceAndLog(next http.Handler) http.Handler {
	return next
}

// Idempotency validates the Idempotency-Key header required on all POST/PUT endpoints.
// TODO(mopro:placeholder): implement idempotency key validation and deduplication
// Unblocked by: Phase 1 (HTTP server and idempotency store)
func Idempotency(next http.Handler) http.Handler {
	return next
}

// Locale extracts locale from Accept-Language / user profile and stores it in context.
// TODO(mopro:placeholder): implement locale extraction and context injection
// Unblocked by: Phase 1 (identity module integration)
func Locale(next http.Handler) http.Handler {
	return next
}
