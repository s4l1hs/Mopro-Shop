package shipping_test

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/shipping"
)

// ── stubs ─────────────────────────────────────────────────────────────────────

type stubOrderSvc struct {
	mu                 sync.Mutex
	markDeliveredCalls int
}

func (s *stubOrderSvc) MarkDelivered(_ context.Context, _ int64, _ time.Time) error {
	s.mu.Lock()
	s.markDeliveredCalls++
	s.mu.Unlock()
	return nil
}
func (s *stubOrderSvc) Checkout(_ context.Context, _ order.CheckoutRequest) (order.Order, []order.OrderItem, error) {
	return order.Order{}, nil, nil
}
func (s *stubOrderSvc) GetOrder(_ context.Context, _ int64) (order.Order, []order.OrderItem, error) {
	return order.Order{}, nil, nil
}
func (s *stubOrderSvc) ListOrders(_ context.Context, _ int64) ([]order.Order, error) { return nil, nil }
func (s *stubOrderSvc) UpdateStatus(_ context.Context, _ int64, _ order.OrderStatus) error {
	return nil
}
func (s *stubOrderSvc) CancelOrder(_ context.Context, _ int64, _ string) error { return nil }
func (s *stubOrderSvc) InitiateCheckout(_ context.Context, _ order.InitiateCheckoutRequest) (order.InitiateCheckoutResponse, error) {
	return order.InitiateCheckoutResponse{}, nil
}
func (s *stubOrderSvc) MarkPaid(_ context.Context, _ int64) error { return nil }
func (s *stubOrderSvc) ValidateCoupon(_ context.Context, _ string, _ int64, _ string, _ int64) (order.CouponValidation, error) {
	return order.CouponValidation{}, nil
}

// stubShippingRepo is an in-memory shipping.Repository for testing.
type stubShippingRepo struct {
	mu        sync.Mutex
	shipments map[string]shipping.Shipment // key: carrier:trackingNumber
	states    map[int64]shipping.ShipmentState
	events    []shipping.ShipmentEvent

	// P-034 ETA reference data (in-memory).
	transit     map[string][2]int // key: "originCity:destCity" → {min,max}
	transitDef  [2]int            // national fallback {min,max}
	hasTransDef bool
}

func newStubRepo(carrier, tracking string, orderID int64) *stubShippingRepo {
	r := &stubShippingRepo{
		shipments: map[string]shipping.Shipment{},
		states:    map[int64]shipping.ShipmentState{},
	}
	r.shipments[carrier+":"+tracking] = shipping.Shipment{
		ID:             42,
		OrderID:        orderID,
		Carrier:        carrier,
		TrackingNumber: tracking,
		State:          shipping.ShipmentStateInTransit,
	}
	r.states[42] = shipping.ShipmentStateInTransit
	return r
}

func (r *stubShippingRepo) InsertShipment(_ context.Context, _ pgx.Tx, s shipping.Shipment) (shipping.Shipment, error) {
	return s, nil
}
func (r *stubShippingRepo) FindShipmentByOrderID(_ context.Context, _ int64) (shipping.Shipment, error) {
	return shipping.Shipment{}, shipping.ErrShipmentNotFound
}
func (r *stubShippingRepo) FindShipmentByTrackingNumber(_ context.Context, carrier, tracking string) (shipping.Shipment, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	s, ok := r.shipments[carrier+":"+tracking]
	if !ok {
		return shipping.Shipment{}, shipping.ErrShipmentNotFound
	}
	return s, nil
}
func (r *stubShippingRepo) UpdateShipmentState(_ context.Context, _ pgx.Tx, id int64, state shipping.ShipmentState, _ *time.Time) error {
	r.mu.Lock()
	r.states[id] = state
	r.mu.Unlock()
	return nil
}
func (r *stubShippingRepo) InsertShipmentEvent(_ context.Context, _ pgx.Tx, e shipping.ShipmentEvent) error {
	r.mu.Lock()
	r.events = append(r.events, e)
	r.mu.Unlock()
	return nil
}
func (r *stubShippingRepo) FindPollableShipments(_ context.Context, _ string, _ int) ([]shipping.Shipment, error) {
	return nil, nil
}
func (r *stubShippingRepo) UpdateLastPolledAt(_ context.Context, _ int64) error { return nil }
func (r *stubShippingRepo) WithTx(_ context.Context, fn func(pgx.Tx) error) error {
	return fn(nil)
}
func (r *stubShippingRepo) LookupTransit(_ context.Context, _, originCity, destCity string) (int, int, bool, error) {
	v, ok := r.transit[originCity+":"+destCity]
	if !ok {
		return 0, 0, false, nil
	}
	return v[0], v[1], true, nil
}
func (r *stubShippingRepo) LookupTransitDefault(_ context.Context, _ string) (int, int, bool, error) {
	if !r.hasTransDef {
		return 0, 0, false, nil
	}
	return r.transitDef[0], r.transitDef[1], true, nil
}

// stubAdapter returns a delivered event for any input.
type stubAdapter struct{}

func (a *stubAdapter) CalculateRate(_ context.Context, _ shipping.ShipmentInput) (shipping.RateResult, error) {
	return shipping.RateResult{}, nil
}
func (a *stubAdapter) CreateLabel(_ context.Context, _ shipping.ShipmentInput) (shipping.ShipmentResult, error) {
	return shipping.ShipmentResult{}, nil
}
func (a *stubAdapter) TrackShipment(_ context.Context, _ string) (shipping.TrackResult, error) {
	return shipping.TrackResult{State: shipping.ShipmentStateDelivered, EventAt: time.Now().UTC()}, nil
}
func (a *stubAdapter) CreateReturnLabel(_ context.Context, _ int64) (shipping.ShipmentResult, error) {
	return shipping.ShipmentResult{}, nil
}
func (a *stubAdapter) HandleWebhook(_ context.Context, _ []byte, _ map[string]string) (shipping.WebhookEvent, error) {
	return shipping.WebhookEvent{State: shipping.ShipmentStateDelivered, EventAt: time.Now().UTC()}, nil
}
func (a *stubAdapter) CancelShipment(_ context.Context, _ string) error { return nil }

// ── tests ──────────────────────────────────────────────────────────────────────

// TestProcessWebhookEvent_Delivered verifies that ProcessWebhookEvent calls
// order.MarkDelivered exactly once for a delivered event.
func TestProcessWebhookEvent_Delivered(t *testing.T) {
	const carrier = "surat"
	const tracking = "SURAT-TEST-001"
	const orderID = int64(99)

	repo := newStubRepo(carrier, tracking, orderID)
	orderSvc := &stubOrderSvc{}
	svc, err := shipping.NewService("surat",
		map[string]shipping.Adapter{"surat": &stubAdapter{}}, repo, orderSvc, false)
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}

	event := shipping.WebhookEvent{
		TrackingNumber: tracking,
		State:          shipping.ShipmentStateDelivered,
		EventAt:        time.Now().UTC(),
	}
	if err := svc.ProcessWebhookEvent(context.Background(), carrier, event); err != nil {
		t.Fatalf("ProcessWebhookEvent: %v", err)
	}

	orderSvc.mu.Lock()
	calls := orderSvc.markDeliveredCalls
	orderSvc.mu.Unlock()
	if calls != 1 {
		t.Errorf("MarkDelivered calls: want 1, got %d", calls)
	}
	if repo.states[42] != shipping.ShipmentStateDelivered {
		t.Errorf("shipment state: want delivered, got %s", repo.states[42])
	}
}

// TestProcessWebhookEvent_NonDelivered verifies that non-delivered states do NOT
// trigger order.MarkDelivered.
func TestProcessWebhookEvent_NonDelivered(t *testing.T) {
	const carrier = "surat"
	const tracking = "SURAT-TRANSIT-001"

	repo := newStubRepo(carrier, tracking, 100)
	orderSvc := &stubOrderSvc{}
	svc, _ := shipping.NewService("surat",
		map[string]shipping.Adapter{"surat": &stubAdapter{}}, repo, orderSvc, false)

	event := shipping.WebhookEvent{
		TrackingNumber: tracking,
		State:          shipping.ShipmentStateInTransit,
		EventAt:        time.Now().UTC(),
	}
	if err := svc.ProcessWebhookEvent(context.Background(), carrier, event); err != nil {
		t.Fatalf("ProcessWebhookEvent: %v", err)
	}

	orderSvc.mu.Lock()
	calls := orderSvc.markDeliveredCalls
	orderSvc.mu.Unlock()
	if calls != 0 {
		t.Errorf("MarkDelivered must not be called for in_transit; got %d calls", calls)
	}
}

// TestProcessWebhookEvent_UnknownTracking verifies that an unknown tracking number
// returns nil (prevents carrier retry).
func TestProcessWebhookEvent_UnknownTracking(t *testing.T) {
	repo := newStubRepo("surat", "KNOWN-001", 1)
	svc, _ := shipping.NewService("surat",
		map[string]shipping.Adapter{"surat": &stubAdapter{}}, repo, &stubOrderSvc{}, false)

	err := svc.ProcessWebhookEvent(context.Background(), "surat", shipping.WebhookEvent{
		TrackingNumber: "UNKNOWN-999",
		State:          shipping.ShipmentStateDelivered,
	})
	if err != nil {
		t.Errorf("unknown tracking must return nil, got: %v", err)
	}
}

// TestProcessWebhookEvent_Concurrent verifies no data race when the same
// delivered event is processed concurrently (-race detector).
func TestProcessWebhookEvent_Concurrent(t *testing.T) {
	const carrier = "surat"
	const tracking = "SURAT-RACE-001"
	const N = 20

	repo := newStubRepo(carrier, tracking, 200)
	orderSvc := &stubOrderSvc{}
	svc, _ := shipping.NewService("surat",
		map[string]shipping.Adapter{"surat": &stubAdapter{}}, repo, orderSvc, false)

	event := shipping.WebhookEvent{
		TrackingNumber: tracking,
		State:          shipping.ShipmentStateDelivered,
		EventAt:        time.Now().UTC(),
	}

	var wg sync.WaitGroup
	for i := 0; i < N; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_ = svc.ProcessWebhookEvent(context.Background(), carrier, event)
		}()
	}
	wg.Wait()

	orderSvc.mu.Lock()
	calls := orderSvc.markDeliveredCalls
	orderSvc.mu.Unlock()
	if calls == 0 {
		t.Error("MarkDelivered should be called at least once")
	}
	// The -race flag verifies no concurrent map/slice writes under the hood.
}

// TestNewService_ProductionGuardMissingDefault verifies that GO_ENV=production
// with empty KARGO_DEFAULT returns an error.
func TestNewService_ProductionGuardMissingDefault(t *testing.T) {
	// A-003: production is now the injected inProduction=true arg (was t.Setenv GO_ENV).
	_, err := shipping.NewService("", map[string]shipping.Adapter{}, nil, nil, true)
	if err == nil {
		t.Error("expected error for empty KARGO_DEFAULT in production")
	}
}

// TestNewService_ProductionGuardMissingAdapter verifies that GO_ENV=production
// with KARGO_DEFAULT set but no adapter returns an error.
func TestNewService_ProductionGuardMissingAdapter(t *testing.T) {
	_, err := shipping.NewService("aras", map[string]shipping.Adapter{}, nil, nil, true)
	if err == nil {
		t.Error("expected error: KARGO_DEFAULT=aras adapter not configured")
	}
}

// ── P-034 EstimateETA ───────────────────────────────────────────────────────────

// newETARepo builds a stub repo seeded with a single transit row and a national
// fallback, for the EstimateETA tests.
func newETARepo() *stubShippingRepo {
	return &stubShippingRepo{
		transit:     map[string][2]int{"istanbul:ankara": {2, 3}},
		transitDef:  [2]int{2, 5},
		hasTransDef: true,
	}
}

func etaService(t *testing.T, repo *stubShippingRepo) shipping.Service {
	t.Helper()
	svc, err := shipping.NewService("surat",
		map[string]shipping.Adapter{"surat": &stubAdapter{}}, repo, &stubOrderSvc{}, false)
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}
	return svc
}

func TestEstimateETA_ConfidentZonePair(t *testing.T) {
	svc := etaService(t, newETARepo())
	dest := "Ankara"
	got, err := svc.EstimateETA(context.Background(), "TR", "istanbul", &dest)
	if err != nil {
		t.Fatalf("EstimateETA: %v", err)
	}
	if !got.Confident || got.MinDays != 2 || got.MaxDays != 3 {
		t.Errorf("want confident 2-3, got %+v", got)
	}
}

func TestEstimateETA_TurkishFoldedDest(t *testing.T) {
	// "İSTANBUL" / "Ankara" with Turkish casing must fold to the ascii keys.
	repo := &stubShippingRepo{
		transit:     map[string][2]int{"istanbul:izmir": {1, 2}},
		transitDef:  [2]int{2, 5},
		hasTransDef: true,
	}
	svc := etaService(t, repo)
	dest := "İzmir"
	got, err := svc.EstimateETA(context.Background(), "TR", "İstanbul", &dest)
	if err != nil {
		t.Fatalf("EstimateETA: %v", err)
	}
	if !got.Confident || got.MinDays != 1 || got.MaxDays != 2 {
		t.Errorf("want confident 1-2 after folding, got %+v", got)
	}
}

func TestEstimateETA_GuestFallsBackToNationalRange(t *testing.T) {
	svc := etaService(t, newETARepo())
	got, err := svc.EstimateETA(context.Background(), "TR", "istanbul", nil) // guest: no dest
	if err != nil {
		t.Fatalf("EstimateETA: %v", err)
	}
	if got.Confident || got.MinDays != 2 || got.MaxDays != 5 {
		t.Errorf("want non-confident 2-5 fallback, got %+v", got)
	}
}

func TestEstimateETA_UnknownPairFallsBack(t *testing.T) {
	svc := etaService(t, newETARepo())
	dest := "Diyarbakir" // no transit row for istanbul:diyarbakir in the stub
	got, err := svc.EstimateETA(context.Background(), "TR", "istanbul", &dest)
	if err != nil {
		t.Fatalf("EstimateETA: %v", err)
	}
	if got.Confident || got.MaxDays != 5 {
		t.Errorf("want non-confident fallback, got %+v", got)
	}
}

func TestEstimateETA_NoDataReturnsEmpty(t *testing.T) {
	repo := &stubShippingRepo{transit: map[string][2]int{}} // no transit, no fallback
	svc := etaService(t, repo)
	dest := "ankara"
	got, err := svc.EstimateETA(context.Background(), "TR", "istanbul", &dest)
	if err != nil {
		t.Fatalf("EstimateETA: %v", err)
	}
	if got.MaxDays != 0 {
		t.Errorf("want empty (MaxDays 0) when no data, got %+v", got)
	}
}
