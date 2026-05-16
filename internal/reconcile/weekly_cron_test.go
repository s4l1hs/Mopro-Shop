package reconcile

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mopro/platform/pkg/healthcheck"
)

// stubReconcilePinger records which ping methods were called.
type stubReconcilePinger struct {
	started  int
	succeded int
	failed   int
	lastMsg  string
}

func (s *stubReconcilePinger) Start(_ context.Context)   { s.started++ }
func (s *stubReconcilePinger) Success(_ context.Context) { s.succeded++ }
func (s *stubReconcilePinger) Fail(_ context.Context, msg string) {
	s.failed++
	s.lastMsg = msg
}

type stubWeeklyService struct {
	result WeeklyResult
	err    error
}

func (s *stubWeeklyService) RunWeekly(_ context.Context, _ time.Time) (WeeklyResult, error) {
	return s.result, s.err
}

func TestWeeklyCron_PingerSuccess(t *testing.T) {
	p := &stubReconcilePinger{}
	svc := &stubWeeklyService{result: WeeklyResult{AlertsInserted: 0, Errors: nil}}
	c := NewWeeklyCron(svc, time.UTC, p, nil)
	c.runOnce(context.Background())

	if p.started != 1 {
		t.Errorf("Start calls: got %d, want 1", p.started)
	}
	if p.succeded != 1 {
		t.Errorf("Success calls: got %d, want 1", p.succeded)
	}
	if p.failed != 0 {
		t.Errorf("Fail calls: got %d, want 0", p.failed)
	}
}

func TestWeeklyCron_PingerFailOnError(t *testing.T) {
	p := &stubReconcilePinger{}
	svc := &stubWeeklyService{err: errors.New("db unreachable")}
	c := NewWeeklyCron(svc, time.UTC, p, nil)
	c.runOnce(context.Background())

	if p.started != 1 {
		t.Errorf("Start calls: got %d, want 1", p.started)
	}
	if p.failed != 1 {
		t.Errorf("Fail calls: got %d, want 1", p.failed)
	}
	if p.succeded != 0 {
		t.Errorf("Success calls: got %d, want 0", p.succeded)
	}
}

func TestWeeklyCron_PingerFailOnAlerts(t *testing.T) {
	p := &stubReconcilePinger{}
	svc := &stubWeeklyService{result: WeeklyResult{AlertsInserted: 2}}
	c := NewWeeklyCron(svc, time.UTC, p, nil)
	c.runOnce(context.Background())

	if p.failed != 1 {
		t.Errorf("Fail calls: got %d, want 1", p.failed)
	}
	if p.succeded != 0 {
		t.Errorf("Success calls: got %d, want 0", p.succeded)
	}
}

func TestWeeklyCron_NilPingerDefaultsToNoop(t *testing.T) {
	svc := &stubWeeklyService{result: WeeklyResult{}}
	c := NewWeeklyCron(svc, time.UTC, nil, nil)
	if c.pinger == nil {
		t.Fatal("pinger must not be nil after NewWeeklyCron with nil pinger")
	}
	ctx := context.Background()
	c.pinger.Start(ctx)
	c.pinger.Success(ctx)
	c.pinger.Fail(ctx, "test")
	_ = healthcheck.NewNoop()
}
