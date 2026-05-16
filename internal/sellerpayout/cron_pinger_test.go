package sellerpayout

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mopro/platform/pkg/healthcheck"
)

// stubPinger records which ping methods were called.
type stubPinger struct {
	started  int
	succeded int
	failed   int
	lastMsg  string
}

func (s *stubPinger) Start(_ context.Context)   { s.started++ }
func (s *stubPinger) Success(_ context.Context) { s.succeded++ }
func (s *stubPinger) Fail(_ context.Context, msg string) {
	s.failed++
	s.lastMsg = msg
}

// stubDailyService implements Service minimally for cron pinger tests.
type stubDailyService struct {
	result RunDailyResult
	err    error
}

func (s *stubDailyService) RunDailyPayouts(_ context.Context, _ time.Time, _, _ string) (RunDailyResult, error) {
	return s.result, s.err
}
func (s *stubDailyService) HandleOrderDelivered(_ context.Context, _ OrderDeliveredEvent) error {
	return nil
}
func (s *stubDailyService) SchedulePayoutsForOrder(_ context.Context, _ OrderDeliveredEvent) error {
	return nil
}
func (s *stubDailyService) HandlePspOnboarded(_ context.Context, _ PspOnboardedEvent) error {
	return nil
}
func (s *stubDailyService) HandleFraudHoldSet(_ context.Context, _ FraudHoldSetEvent) error {
	return nil
}
func (s *stubDailyService) ReconcileProcessing(_ context.Context) error { return nil }

func TestDailyCron_PingerSuccess(t *testing.T) {
	p := &stubPinger{}
	svc := &stubDailyService{result: RunDailyResult{Batched: 2, Paid: 2}}
	d := NewDailyCron(svc, "TR", "TRY", time.UTC, p, nil)

	d.runDaily()

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

func TestDailyCron_PingerFailOnError(t *testing.T) {
	p := &stubPinger{}
	svc := &stubDailyService{err: errors.New("db down")}
	d := NewDailyCron(svc, "TR", "TRY", time.UTC, p, nil)

	d.runDaily()

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

func TestDailyCron_PingerFailOnPartialFailure(t *testing.T) {
	p := &stubPinger{}
	svc := &stubDailyService{result: RunDailyResult{Batched: 5, Paid: 3, Failed: 2}}
	d := NewDailyCron(svc, "TR", "TRY", time.UTC, p, nil)

	d.runDaily()

	if p.failed != 1 {
		t.Errorf("Fail calls: got %d, want 1", p.failed)
	}
	if p.succeded != 0 {
		t.Errorf("Success calls: got %d, want 0", p.succeded)
	}
}

func TestDailyCron_NilPingerDefaultsToNoop(t *testing.T) {
	svc := &stubDailyService{result: RunDailyResult{}}
	d := NewDailyCron(svc, "TR", "TRY", time.UTC, nil, nil)
	if d.pinger == nil {
		t.Fatal("pinger must not be nil after NewDailyCron with nil pinger")
	}
	// Ensure it is a no-op (satisfies Pinger interface without panic)
	ctx := context.Background()
	d.pinger.Start(ctx)
	d.pinger.Success(ctx)
	d.pinger.Fail(ctx, "test")
	_ = healthcheck.NewNoop() // compile-time import check
}
