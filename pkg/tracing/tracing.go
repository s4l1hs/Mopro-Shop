// Package tracing is retained for import-path compatibility.
// New code should use pkg/otelx directly.
package tracing

import (
	"context"
	"os"

	"go.opentelemetry.io/otel/sdk/trace"

	"github.com/mopro/platform/pkg/otelx"
)

// Init configures a global TracerProvider with an OTLP gRPC exporter.
// Deprecated: call otelx.Init directly for full configuration control.
func Init(serviceName string) (*trace.TracerProvider, error) {
	_, err := otelx.Init(context.Background(), otelx.Config{
		ServiceName: serviceName,
		Market:      os.Getenv("MARKET"),
	})
	return nil, err
}
