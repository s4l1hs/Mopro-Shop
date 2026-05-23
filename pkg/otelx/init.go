// Package otelx provides OpenTelemetry initialisation and HTTP middleware for Mopro services.
package otelx

import (
	"context"
	"fmt"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// Config holds the options for OTel initialisation.
type Config struct {
	// ServiceName is the OTel service.name resource attribute (e.g. "core-svc").
	ServiceName string
	// Market is stored as a resource attribute (e.g. "TR").
	Market string
	// Environment is "dev" or "prod". Defaults to ENV env var, then "prod".
	Environment string
	// OTLPEndpoint is the gRPC endpoint of the OTLP receiver (no scheme).
	// Defaults to "otel-collector:4317".
	OTLPEndpoint string
}

// Init configures the global OTel TracerProvider with an OTLP gRPC exporter.
// The caller MUST defer the returned shutdown func to flush pending spans.
//
//	shutdown, err := otelx.Init(ctx, cfg)
//	if err != nil { ... }
//	defer shutdown(context.Background())
//
// AlwaysSample is used when Environment="dev"; otherwise ParentBased(TraceIDRatio=0.1).
func Init(ctx context.Context, cfg Config) (func(context.Context) error, error) {
	if cfg.OTLPEndpoint == "" {
		cfg.OTLPEndpoint = "otel-collector:4317"
	}
	if cfg.Environment == "" {
		cfg.Environment = os.Getenv("ENV")
		if cfg.Environment == "" {
			cfg.Environment = "prod"
		}
	}

	exp, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(cfg.OTLPEndpoint),
		otlptracegrpc.WithInsecure(),
		otlptracegrpc.WithTimeout(5*time.Second),
	)
	if err != nil {
		return nil, fmt.Errorf("otelx: create OTLP exporter: %w", err)
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(cfg.ServiceName),
			attribute.String("deployment.environment", cfg.Environment),
			attribute.String("market", cfg.Market),
		),
	)
	if err != nil {
		// resource.New can fail only for the OS-level resource detectors;
		// fall back to a minimal resource rather than crashing.
		res = resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(cfg.ServiceName),
			attribute.String("deployment.environment", cfg.Environment),
			attribute.String("market", cfg.Market),
		)
	}

	sampler := sdktrace.ParentBased(sdktrace.TraceIDRatioBased(0.1))
	if cfg.Environment == "dev" {
		sampler = sdktrace.AlwaysSample()
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exp),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sampler),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tp.Shutdown, nil
}
