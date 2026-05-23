package cashback

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mopro/platform/pkg/timex"
)

func newTestSvc(repo Repository) Service {
	return NewService(repo, &mockCronOutbox{}, nil, "TRY_COIN", &mockWalletPoster{}, nil)
}

func newTestSvcWithCal(repo Repository) Service {
	cal := timex.NewStaticCalendarLoader(map[string]timex.Calendar{"TR": {}})
	return NewService(repo, &mockCronOutbox{}, cal, "TRY_COIN", &mockWalletPoster{}, nil)
}

// ── CreatePlanFromDelivery ────────────────────────────────────────────────────

func TestCreatePlanFromDelivery_HappyPath(t *testing.T) {
	repo := &mockCashbackRepo{}
	svc := newTestSvcWithCal(repo)

	ev := OrderDeliveredEvent{
		OrderID:       1001,
		UserID:        42,
		DeliveredAt:   time.Now().AddDate(0, -1, 0),
		Market:        "TR",
		Currency:      "TRY",
		PriceMinor:    1_000_000,
		CommissionBps: 2000,
		ProductID:     7,
		ProductTitle:  "Test Ürün",
	}
	plan, err := svc.CreatePlanFromDelivery(context.Background(), ev)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if plan.OrderID != ev.OrderID {
		t.Errorf("OrderID: got %d, want %d", plan.OrderID, ev.OrderID)
	}
	if plan.TotalMonths != 78 {
		t.Errorf("TotalMonths: got %d, want 78", plan.TotalMonths)
	}
	if plan.MonthlyAmountMinor != 12820 {
		t.Errorf("MonthlyAmountMinor: got %d, want 12820", plan.MonthlyAmountMinor)
	}
	if plan.MonthlyAmountLastMinor != 12860 {
		t.Errorf("MonthlyAmountLastMinor: got %d, want 12860", plan.MonthlyAmountLastMinor)
	}
	if plan.Currency != "TRY_COIN" {
		t.Errorf("Currency: got %q, want TRY_COIN", plan.Currency)
	}
	if plan.ProductID != 7 {
		t.Errorf("ProductID: got %d, want 7", plan.ProductID)
	}
	if plan.Status != PlanStatusActive {
		t.Errorf("Status: got %q, want active", plan.Status)
	}
}

func TestCreatePlanFromDelivery_Idempotent_ReturnsExisting(t *testing.T) {
	existing := Plan{ID: 99, OrderID: 1001, TotalMonths: 78}
	repo := &mockCashbackRepo{
		insertPlanRet:   existing,
		insertPlanIsNew: false,
	}
	svc := newTestSvc(repo)

	ev := OrderDeliveredEvent{
		OrderID:       1001,
		UserID:        42,
		DeliveredAt:   time.Now(),
		Market:        "TR",
		PriceMinor:    1_000_000,
		CommissionBps: 2000,
	}
	plan, err := svc.CreatePlanFromDelivery(context.Background(), ev)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if plan.ID != 99 {
		t.Errorf("should return existing plan id=99, got id=%d", plan.ID)
	}
}

func TestCreatePlanFromDelivery_ZeroPrice_ReturnedSilently(t *testing.T) {
	repo := &mockCashbackRepo{}
	svc := newTestSvc(repo)

	ev := OrderDeliveredEvent{OrderID: 1, UserID: 1, PriceMinor: 0, CommissionBps: 2000}
	plan, err := svc.CreatePlanFromDelivery(context.Background(), ev)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if plan.ID != 0 {
		t.Errorf("expected zero plan for zero price, got id=%d", plan.ID)
	}
}

func TestCreatePlanFromDelivery_InvalidCommissionBps_Error(t *testing.T) {
	repo := &mockCashbackRepo{}
	svc := newTestSvc(repo)

	ev := OrderDeliveredEvent{OrderID: 1, UserID: 1, PriceMinor: 1_000_000, CommissionBps: 50}
	_, err := svc.CreatePlanFromDelivery(context.Background(), ev)
	if err == nil {
		t.Fatal("expected error for commissionBps=50")
	}
	if !errors.Is(err, ErrInvalidPlanInput) {
		t.Errorf("expected ErrInvalidPlanInput in error chain, got %v", err)
	}
}

func TestCreatePlanFromDelivery_InsertError_Propagated(t *testing.T) {
	repo := &mockCashbackRepo{insertPlanErr: errors.New("db unavailable")}
	svc := newTestSvc(repo)

	ev := OrderDeliveredEvent{OrderID: 1, UserID: 1, PriceMinor: 1_000_000, CommissionBps: 2000}
	_, err := svc.CreatePlanFromDelivery(context.Background(), ev)
	if err == nil {
		t.Fatal("expected error when InsertPlanIfAbsent returns error")
	}
}
