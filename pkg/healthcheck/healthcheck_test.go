package healthcheck_test

import (
	"context"
	"log/slog"
	"testing"
	"time"

	"github.com/mopro/platform/pkg/healthcheck"
)

func TestNewFromUUID_EmptyReturnsNoop(t *testing.T) {
	p := healthcheck.NewFromUUID("", 5*time.Second, slog.Default())
	ctx := context.Background()
	p.Start(ctx)
	p.Success(ctx)
	p.Fail(ctx, "test error")
}

func TestNewFromUUID_BuildsURL(t *testing.T) {
	uuid := "12345678-1234-1234-1234-123456789abc"
	p := healthcheck.NewFromUUID(uuid, 5*time.Second, slog.Default())
	got := healthcheck.GetPingerBaseURL(p)
	want := "https://hc-ping.com/" + uuid
	if got != want {
		t.Errorf("NewFromUUID URL: got %q, want %q", got, want)
	}
}
