// Package tracing initialises OpenTelemetry distributed tracing for Grafana Tempo.
package tracing

import (
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/sdk/trace"
)

// Init configures a global TracerProvider for the named service.
// TODO(mopro:placeholder): configure OTLP exporter pointing at Grafana Agent
// Unblocked by: Phase 1 (GRAFANA_TEMPO_* env vars and deploy/grafana-agent/agent.yaml)
func Init(serviceName string) (*trace.TracerProvider, error) {
	tp := trace.NewTracerProvider()
	otel.SetTracerProvider(tp)
	_ = serviceName
	return tp, nil
}
