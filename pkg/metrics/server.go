package metrics

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// StartServer starts a dedicated HTTP server on addr that serves /metrics in
// Prometheus text exposition format. It is intended to be listened on by
// grafana-agent only, bound to an internal Docker network port.
//
// The server shuts down when ctx is cancelled. Returns a blocking function
// that callers should run in a goroutine. Logs errors via log.
//
// Usage:
//
//	go metrics.StartServer(ctx, reg, "0.0.0.0:9100", slog.Default())
func StartServer(ctx context.Context, reg *Registry, addr string, log *slog.Logger) {
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(
		reg.Prometheus(),
		promhttp.HandlerOpts{
			EnableOpenMetrics: false,
			Registry:          reg.Prometheus(),
		},
	))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	srv := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutCtx); err != nil {
			log.Warn("metrics: /metrics server shutdown error", "err", err)
		}
	}()

	log.Info("metrics: /metrics server starting", "addr", addr, "service", reg.Service())
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		log.Error("metrics: /metrics server exited unexpectedly", "addr", addr, "err", err)
	}
}
