package order

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// ── in-memory fakes ───────────────────────────────────────────────────────────

type fakeOrderRepo struct {
	Repository
	order Order
	items []OrderItem
	err   error
}

func (f *fakeOrderRepo) GetOrder(_ context.Context, _ int64) (Order, []OrderItem, error) {
	if f.err != nil {
		return Order{}, nil, f.err
	}
	return f.order, f.items, nil
}

type fakeReturnRepo struct {
	returnedQty map[int64]int
	insertErr   error // returned by InsertReturnItem (e.g. ErrReturnAlreadyExists)
	created     Return
	items       []ReturnItem
	nextID      int64
	productIDs  []int64             // returned by ReturnProductIDs (seller-scope tests)
	history     []ReturnStatusEvent // RT-04 status timeline
}

func (f *fakeReturnRepo) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	return fn(nil) // fakes ignore tx
}
func (f *fakeReturnRepo) InsertReturn(_ context.Context, _ pgx.Tx, r Return) (Return, error) {
	f.nextID++
	r.ID = f.nextID
	r.CreatedAt = time.Now().UTC()
	r.UpdatedAt = r.CreatedAt
	f.created = r
	return r, nil
}
func (f *fakeReturnRepo) InsertReturnItem(_ context.Context, _ pgx.Tx, it ReturnItem) (ReturnItem, error) {
	if f.insertErr != nil {
		return ReturnItem{}, f.insertErr
	}
	it.ID = int64(len(f.items) + 1)
	f.items = append(f.items, it)
	return it, nil
}
func (f *fakeReturnRepo) InsertReturnStatusHistory(_ context.Context, _ pgx.Tx, _ int64, status, note string) error {
	f.history = append(f.history, ReturnStatusEvent{Status: status, Note: note, CreatedAt: time.Now().UTC()})
	return nil
}
func (f *fakeReturnRepo) ListReturnStatusHistory(_ context.Context, _ int64) ([]ReturnStatusEvent, error) {
	return f.history, nil
}
func (f *fakeReturnRepo) GetReturn(_ context.Context, _ int64) (Return, []ReturnItem, error) {
	return f.created, f.items, nil
}
func (f *fakeReturnRepo) ListReturnsByUser(_ context.Context, _ int64, _, _ int) ([]Return, error) {
	return []Return{f.created}, nil
}
func (f *fakeReturnRepo) ReturnedQtyByOrder(_ context.Context, _ int64) (map[int64]int, error) {
	if f.returnedQty == nil {
		return map[int64]int{}, nil
	}
	return f.returnedQty, nil
}
func (f *fakeReturnRepo) ListReturnsByProductIDs(_ context.Context, _ []int64, status string, _, _ int) ([]Return, error) {
	if status != "" && string(f.created.Status) != status {
		return []Return{}, nil
	}
	return []Return{f.created}, nil
}
func (f *fakeReturnRepo) ReturnProductIDs(_ context.Context, _ int64) ([]int64, error) {
	return f.productIDs, nil
}
func (f *fakeReturnRepo) UpdateReturnStatus(_ context.Context, _ pgx.Tx, _ int64, status string) error {
	f.created.Status = ReturnStatus(status)
	return nil
}

func deliveredOrder(daysAgo int) Order {
	d := time.Now().UTC().AddDate(0, 0, -daysAgo)
	return Order{ID: 1, UserID: 7, Status: StatusDelivered, DeliveredAt: &d, Currency: "TRY", TotalMinor: 10000}
}

func svcWith(o Order, items []OrderItem, rr *fakeReturnRepo) *returnService {
	return &returnService{
		orders:  &fakeOrderRepo{order: o, items: items},
		returns: rr,
		now:     func() time.Time { return time.Now().UTC() },
	}
}

// ── GetReturnHistory (RT-04) ──────────────────────────────────────────────────

func TestGetReturnHistory_OwnerSeesTimeline(t *testing.T) {
	rr := &fakeReturnRepo{created: Return{ID: 5, UserID: 7}}
	rr.history = []ReturnStatusEvent{
		{Status: "pending", Note: "submitted"},
		{Status: "approved", Note: "seller approved"},
	}
	s := svcWith(deliveredOrder(1), nil, rr)

	got, err := s.GetReturnHistory(context.Background(), 7, 5)
	if err != nil {
		t.Fatalf("owner GetReturnHistory: %v", err)
	}
	if len(got) != 2 || got[0].Status != "pending" || got[1].Status != "approved" {
		t.Errorf("history = %+v, want [pending, approved]", got)
	}
}

func TestGetReturnHistory_NonOwnerDenied(t *testing.T) {
	rr := &fakeReturnRepo{created: Return{ID: 5, UserID: 7}, history: []ReturnStatusEvent{{Status: "pending"}}}
	s := svcWith(deliveredOrder(1), nil, rr)

	if _, err := s.GetReturnHistory(context.Background(), 99, 5); !errors.Is(err, ErrReturnNotFound) {
		t.Errorf("non-owner: want ErrReturnNotFound, got %v", err)
	}
}

// ── ComputeActions ────────────────────────────────────────────────────────────

func TestComputeActions_CanCancelOnlyPreShipment(t *testing.T) {
	rr := &fakeReturnRepo{}
	for _, tc := range []struct {
		st   OrderStatus
		want bool
	}{
		{StatusPendingPayment, true}, {StatusPaid, true},
		{StatusShipped, false}, {StatusDelivered, false}, {StatusCancelled, false},
	} {
		s := svcWith(Order{ID: 1, Status: tc.st}, nil, rr)
		act, err := s.ComputeActions(context.Background(), Order{ID: 1, Status: tc.st}, nil)
		if err != nil {
			t.Fatalf("status %s: %v", tc.st, err)
		}
		if act.CanCancel != tc.want {
			t.Errorf("status %s: canCancel=%v want %v", tc.st, act.CanCancel, tc.want)
		}
	}
}

func TestComputeActions_ReturnableWithinWindow(t *testing.T) {
	o := deliveredOrder(2)
	items := []OrderItem{{ID: 10, Qty: 2, UnitPriceMinor: 5000}, {ID: 11, Qty: 1, UnitPriceMinor: 3000}}
	s := svcWith(o, items, &fakeReturnRepo{returnedQty: map[int64]int{10: 1}}) // 1 of item 10 already returned
	act, err := s.ComputeActions(context.Background(), o, items)
	if err != nil {
		t.Fatal(err)
	}
	if !act.CanReturn {
		t.Fatal("want canReturn=true within window")
	}
	if act.ReturnableUntil == nil {
		t.Fatal("want returnableUntil set")
	}
	wantUntil := o.DeliveredAt.AddDate(0, 0, ReturnWindowDays)
	if !act.ReturnableUntil.Equal(wantUntil) {
		t.Errorf("returnableUntil=%v want %v", act.ReturnableUntil, wantUntil)
	}
	// item 10: 2-1=1 remaining; item 11: 1 remaining
	got := map[int64]int{}
	for _, ri := range act.ReturnableItems {
		got[ri.ItemID] = ri.MaxQuantity
	}
	if got[10] != 1 || got[11] != 1 {
		t.Errorf("returnableItems=%v want {10:1, 11:1}", got)
	}
}

func TestComputeActions_NotReturnablePastWindow(t *testing.T) {
	o := deliveredOrder(20) // beyond 14-day window
	items := []OrderItem{{ID: 10, Qty: 1, UnitPriceMinor: 5000}}
	s := svcWith(o, items, &fakeReturnRepo{})
	act, err := s.ComputeActions(context.Background(), o, items)
	if err != nil {
		t.Fatal(err)
	}
	if act.CanReturn {
		t.Error("want canReturn=false past window")
	}
}

// ── CreateReturn validation ───────────────────────────────────────────────────

func TestCreateReturn_HappyPath(t *testing.T) {
	o := deliveredOrder(1)
	items := []OrderItem{{ID: 10, Qty: 2, UnitPriceMinor: 5000}, {ID: 11, Qty: 1, UnitPriceMinor: 3000}}
	rr := &fakeReturnRepo{}
	s := svcWith(o, items, rr)
	rec, ri, err := s.CreateReturn(context.Background(), ReturnInput{
		OrderID: 1, UserID: 7, Reason: ReasonDamaged,
		Items: []ReturnItemInput{{OrderItemID: 10, Quantity: 2}, {OrderItemID: 11, Quantity: 1}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Status != ReturnPending {
		t.Errorf("status=%s want pending", rec.Status)
	}
	if len(ri) != 2 {
		t.Errorf("items=%d want 2", len(ri))
	}
	// refund = 2*5000 + 1*3000 = 13000
	if rec.RefundAmountMinor != 13000 {
		t.Errorf("refund=%d want 13000", rec.RefundAmountMinor)
	}
}

func TestCreateReturn_Rejections(t *testing.T) {
	o := deliveredOrder(1)
	items := []OrderItem{{ID: 10, Qty: 2, UnitPriceMinor: 5000}}

	cases := []struct {
		name string
		in   ReturnInput
		repo *fakeReturnRepo
		ord  Order
		want error
	}{
		{"item not in order", ReturnInput{OrderID: 1, UserID: 7, Reason: ReasonDamaged, Items: []ReturnItemInput{{OrderItemID: 999, Quantity: 1}}}, &fakeReturnRepo{}, o, ErrItemNotInOrder},
		{"qty exceeds returnable", ReturnInput{OrderID: 1, UserID: 7, Reason: ReasonDamaged, Items: []ReturnItemInput{{OrderItemID: 10, Quantity: 5}}}, &fakeReturnRepo{}, o, ErrQuantityExceedsReturn},
		{"invalid reason", ReturnInput{OrderID: 1, UserID: 7, Reason: ReturnReason("bogus"), Items: []ReturnItemInput{{OrderItemID: 10, Quantity: 1}}}, &fakeReturnRepo{}, o, ErrInvalidReturnReason},
		{"not delivered", ReturnInput{OrderID: 1, UserID: 7, Reason: ReasonDamaged, Items: []ReturnItemInput{{OrderItemID: 10, Quantity: 1}}}, &fakeReturnRepo{}, Order{ID: 1, UserID: 7, Status: StatusPaid}, ErrOrderNotDelivered},
		{"window expired", ReturnInput{OrderID: 1, UserID: 7, Reason: ReasonDamaged, Items: []ReturnItemInput{{OrderItemID: 10, Quantity: 1}}}, &fakeReturnRepo{}, deliveredOrder(30), ErrReturnWindowExpired},
		{"duplicate item (unique)", ReturnInput{OrderID: 1, UserID: 7, Reason: ReasonDamaged, Items: []ReturnItemInput{{OrderItemID: 10, Quantity: 1}}}, &fakeReturnRepo{insertErr: ErrReturnAlreadyExists}, o, ErrReturnAlreadyExists},
		{"wrong owner", ReturnInput{OrderID: 1, UserID: 999, Reason: ReasonDamaged, Items: []ReturnItemInput{{OrderItemID: 10, Quantity: 1}}}, &fakeReturnRepo{}, o, ErrOrderNotFound},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := svcWith(tc.ord, items, tc.repo)
			_, _, err := s.CreateReturn(context.Background(), tc.in)
			if !errors.Is(err, tc.want) {
				t.Errorf("got %v want %v", err, tc.want)
			}
		})
	}
}

// ── Seller-side approve / reject (Tranche 5a) ─────────────────────────────────

func pendingReturn() Return {
	return Return{ID: 5, OrderID: 1, UserID: 7, Status: ReturnPending, Reason: ReasonDamaged}
}

func TestSellerApprove_TransitionsPendingToApproved(t *testing.T) {
	rr := &fakeReturnRepo{created: pendingReturn(), productIDs: []int64{10, 11}}
	s := svcWith(deliveredOrder(2), nil, rr)
	rec, err := s.SellerApprove(context.Background(), 5, []int64{11, 99}) // 11 overlaps
	if err != nil {
		t.Fatalf("SellerApprove: %v", err)
	}
	if rec.Status != ReturnApproved {
		t.Errorf("status=%s want approved", rec.Status)
	}
}

func TestSellerReject_TransitionsPendingToRejected(t *testing.T) {
	rr := &fakeReturnRepo{created: pendingReturn(), productIDs: []int64{10}}
	s := svcWith(deliveredOrder(2), nil, rr)
	rec, err := s.SellerReject(context.Background(), 5, []int64{10}, "out_of_policy", "too late")
	if err != nil {
		t.Fatalf("SellerReject: %v", err)
	}
	if rec.Status != ReturnRejected {
		t.Errorf("status=%s want rejected", rec.Status)
	}
}

func TestSellerApprove_RejectsWhenReturnNotOwned(t *testing.T) {
	rr := &fakeReturnRepo{created: pendingReturn(), productIDs: []int64{10}}
	s := svcWith(deliveredOrder(2), nil, rr)
	// Seller owns {77}, return references {10} → no overlap.
	if _, err := s.SellerApprove(context.Background(), 5, []int64{77}); !errors.Is(err, ErrReturnNotOwned) {
		t.Fatalf("want ErrReturnNotOwned, got %v", err)
	}
	// Empty seller product set is likewise not owned.
	if _, err := s.SellerApprove(context.Background(), 5, nil); !errors.Is(err, ErrReturnNotOwned) {
		t.Fatalf("empty scope: want ErrReturnNotOwned, got %v", err)
	}
}

func TestSellerApprove_RejectsWhenNotPending(t *testing.T) {
	r := pendingReturn()
	r.Status = ReturnApproved // already transitioned
	rr := &fakeReturnRepo{created: r, productIDs: []int64{10}}
	s := svcWith(deliveredOrder(2), nil, rr)
	if _, err := s.SellerApprove(context.Background(), 5, []int64{10}); !errors.Is(err, ErrReturnNotPending) {
		t.Fatalf("want ErrReturnNotPending, got %v", err)
	}
}

func TestListSellerReturns_EmptyProductsShortCircuits(t *testing.T) {
	s := svcWith(deliveredOrder(2), nil, &fakeReturnRepo{})
	got, err := s.ListSellerReturns(context.Background(), nil, "", 20, 0)
	if err != nil {
		t.Fatalf("ListSellerReturns: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("want empty, got %d", len(got))
	}
}

func TestListSellerReturns_StatusFilter(t *testing.T) {
	rr := &fakeReturnRepo{created: pendingReturn()}
	s := svcWith(deliveredOrder(2), nil, rr)
	// matching status returns the row
	if got, _ := s.ListSellerReturns(context.Background(), []int64{10}, "pending", 20, 0); len(got) != 1 {
		t.Errorf("status=pending: want 1, got %d", len(got))
	}
	// non-matching status filters it out
	if got, _ := s.ListSellerReturns(context.Background(), []int64{10}, "approved", 20, 0); len(got) != 0 {
		t.Errorf("status=approved: want 0, got %d", len(got))
	}
}
