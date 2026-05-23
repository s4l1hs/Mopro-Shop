// Package logx provides structured logging helpers built on log/slog.
// Setup configures the global default logger; From/Inject/With manage per-request loggers.
package logx

import (
	"log/slog"
	"os"
)

// Setup configures the global slog default logger and returns it.
// JSON format is used in all environments except ENV=dev, which uses text.
// LOG_LEVEL env var controls the minimum level (debug/info/warn/error; default info).
func Setup(svc, market string) *slog.Logger {
	var h slog.Handler
	opts := &slog.HandlerOptions{Level: levelFromEnv()}
	if os.Getenv("ENV") == "dev" {
		h = slog.NewTextHandler(os.Stdout, opts)
	} else {
		h = slog.NewJSONHandler(os.Stdout, opts)
	}
	l := slog.New(h).With(
		slog.String("service", svc),
		slog.String("market", market),
	)
	slog.SetDefault(l)
	return l
}

func levelFromEnv() slog.Level {
	switch os.Getenv("LOG_LEVEL") {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
