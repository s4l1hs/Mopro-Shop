package logx

import (
	"bytes"
	"context"
	"log/slog"
	"strings"
	"testing"
)

func TestSetup_DefaultsToJSON(t *testing.T) {
	t.Setenv("ENV", "")
	t.Setenv("LOG_LEVEL", "")
	l := Setup("test-svc", "TR")
	if l == nil {
		t.Fatal("Setup returned nil logger")
	}
	// Verify it was set as the default.
	if slog.Default() != l {
		t.Error("Setup did not set slog.Default")
	}
}

func TestSetup_DevUsesText(t *testing.T) {
	t.Setenv("ENV", "dev")
	l := Setup("test-svc", "TR")
	if l == nil {
		t.Fatal("Setup returned nil logger")
	}
}

func TestInjectAndFrom_RoundTrip(t *testing.T) {
	buf := &bytes.Buffer{}
	l := slog.New(slog.NewTextHandler(buf, nil))
	ctx := Inject(context.Background(), l)
	got := From(ctx)
	if got != l {
		t.Error("From did not return injected logger")
	}
}

func TestFrom_FallsBackToDefault(t *testing.T) {
	ctx := context.Background()
	got := From(ctx)
	if got == nil {
		t.Error("From returned nil for empty context")
	}
	// Should be slog.Default(), not nil.
}

func TestWith_AddsAttributes(t *testing.T) {
	buf := &bytes.Buffer{}
	l := slog.New(slog.NewTextHandler(buf, nil))
	ctx := Inject(context.Background(), l)
	ctx2 := With(ctx, slog.String("key", "value"))
	From(ctx2).Info("test message")
	out := buf.String()
	if !strings.Contains(out, "key") || !strings.Contains(out, "value") {
		t.Errorf("With did not propagate attributes, got: %s", out)
	}
}

func TestWith_PropagatesExistingAttrs(t *testing.T) {
	buf := &bytes.Buffer{}
	l := slog.New(slog.NewTextHandler(buf, nil)).With(slog.String("existing", "yes"))
	ctx := Inject(context.Background(), l)
	ctx2 := With(ctx, slog.String("extra", "val"))
	From(ctx2).Info("msg")
	out := buf.String()
	if !strings.Contains(out, "existing") {
		t.Errorf("With dropped existing attributes, got: %s", out)
	}
}
