package otelx

import (
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"

	"github.com/mopro/platform/pkg/logx"
	"github.com/mopro/platform/pkg/metrics"
)

const tracerName = "github.com/mopro/platform/pkg/otelx"

// TraceAndLog wraps next with the full observability chain:
//
//	RecoverPanic → InjectTraceContext → StartSpan+InjectLogger+RequestLog
//
// This is the drop-in replacement for pkg/httpx.TraceAndLog.
func TraceAndLog(next http.Handler) http.Handler {
	return RecoverPanic(InjectTraceContext(spanAndLog(next)))
}

// TraceLogAndMetrics wraps next with the full observability chain including
// Prometheus HTTP metrics:
//
//	RecoverPanic → InjectTraceContext → StartSpan+InjectLogger → MetricsHTTP → Handler
//
// Use this instead of TraceAndLog when a *metrics.HTTPMetrics is available
// (all production main.go wiring). Falls back to TraceAndLog when m is nil.
func TraceLogAndMetrics(m *metrics.HTTPMetrics, svc string, next http.Handler) http.Handler {
	if m == nil {
		return TraceAndLog(next)
	}
	return RecoverPanic(InjectTraceContext(spanAndLog(m.Middleware(svc, next))))
}

// InjectTraceContext extracts a W3C traceparent header and injects the remote
// span context into the Go context so StartSpan links to the upstream trace.
func InjectTraceContext(next http.Handler) http.Handler {
	prop := otel.GetTextMapPropagator()
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := prop.Extract(r.Context(), propagation.HeaderCarrier(r.Header))
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// spanAndLog starts an OTel server span, injects a trace-attributed logger
// into the context, then logs the completed request.
func spanAndLog(next http.Handler) http.Handler {
	tracer := otel.GetTracerProvider().Tracer(tracerName)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		route := r.Pattern
		if route == "" {
			route = r.URL.Path
		}
		ctx, span := tracer.Start(r.Context(), route,
			trace.WithSpanKind(trace.SpanKindServer),
			trace.WithAttributes(
				semconv.HTTPRequestMethodKey.String(r.Method),
				semconv.URLPath(r.URL.Path),
				semconv.ServerAddress(r.Host),
			),
		)
		defer span.End()

		// Inject trace_id/span_id into the context logger so every log line
		// emitted inside the handler carries these fields automatically.
		sc := span.SpanContext()
		ctx = logx.With(ctx,
			slog.String("trace_id", sc.TraceID().String()),
			slog.String("span_id", sc.SpanID().String()),
		)

		rw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		start := time.Now()
		next.ServeHTTP(rw, r.WithContext(ctx))

		span.SetAttributes(semconv.HTTPResponseStatusCode(rw.code))
		if rw.code >= 500 {
			span.SetStatus(codes.Error, http.StatusText(rw.code))
		}

		logx.From(ctx).Info("http.request",
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", rw.code),
			slog.Duration("latency", time.Since(start)),
		)
	})
}

// RecoverPanic catches panics, responds 500, and logs with the context logger.
func RecoverPanic(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				span := trace.SpanFromContext(r.Context())
				span.SetStatus(codes.Error, "panic")
				logx.From(r.Context()).Error("http.panic",
					slog.Any("panic", rec),
					slog.String("stack", string(debug.Stack())),
				)
				http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// statusWriter wraps http.ResponseWriter to capture the response status code.
type statusWriter struct {
	http.ResponseWriter
	code    int
	written bool
}

func (sw *statusWriter) WriteHeader(code int) {
	if !sw.written {
		sw.code = code
		sw.written = true
	}
	sw.ResponseWriter.WriteHeader(code)
}

func (sw *statusWriter) Write(b []byte) (int, error) {
	if !sw.written {
		sw.written = true
	}
	return sw.ResponseWriter.Write(b)
}
