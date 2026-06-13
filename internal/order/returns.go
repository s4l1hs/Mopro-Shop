package order

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/outbox"
)

// ReturnWindowDays is the default consumer return window measured from
// delivered_at. Matches the OpenAPI CreateReturn 409 contract ("> 14 days").
const ReturnWindowDays = 14

// Return-flow errors. Validation failures map to HTTP 422 at the handler;
// ErrReturnWindowExpired maps to 409 per the OpenAPI contract.
var (
	ErrReturnNotFound        = errors.New("order: return not found")
	ErrOrderNotDelivered     = errors.New("order: order not delivered; not returnable")
	ErrReturnWindowExpired   = errors.New("order: return window expired")
	ErrItemNotInOrder        = errors.New("order: item not in order")
	ErrQuantityExceedsReturn = errors.New("order: quantity exceeds returnable amount")
	ErrReturnAlreadyExists   = errors.New("order: item already has a return")
	ErrNoReturnableItems     = errors.New("order: no returnable items")
	ErrInvalidReturnReason   = errors.New("order: invalid return reason")
	ErrReturnNotPending      = errors.New("order: return is not pending; cannot transition")
	ErrReturnNotOwned        = errors.New("order: return does not belong to this seller")
	ErrOutboxNotConfigured   = errors.New("order: outbox repository not configured; refund settlement requires it")
)

// ReturnStatus is the per-return lifecycle (distinct from OrderStatus).
type ReturnStatus string

const (
	ReturnPending  ReturnStatus = "pending"
	ReturnApproved ReturnStatus = "approved"
	ReturnRejected ReturnStatus = "rejected"
	ReturnRefunded ReturnStatus = "refunded"
)

// ReturnReason is the (single, per-return) reason enum from the OpenAPI contract.
type ReturnReason string

const (
	ReasonWrongProduct   ReturnReason = "wrong_product"
	ReasonNotAsDescribed ReturnReason = "not_as_described"
	ReasonDamaged        ReturnReason = "damaged"
	ReasonSizeIssue      ReturnReason = "size_issue"
	ReasonChangedMind    ReturnReason = "changed_mind"
	ReasonOther          ReturnReason = "other"
)

func (r ReturnReason) valid() bool {
	switch r {
	case ReasonWrongProduct, ReasonNotAsDescribed, ReasonDamaged,
		ReasonSizeIssue, ReasonChangedMind, ReasonOther:
		return true
	}
	return false
}

// Return is a return-request header.
type Return struct {
	ID                int64        `json:"id"`
	OrderID           int64        `json:"order_id"`
	UserID            int64        `json:"user_id"`
	Status            ReturnStatus `json:"status"`
	Reason            ReturnReason `json:"reason"`
	Description       string       `json:"description"`
	RefundAmountMinor int64        `json:"refund_amount_minor"`
	RefundCurrency    string       `json:"refund_currency"`
	CreatedAt         time.Time    `json:"created_at"`
	UpdatedAt         time.Time    `json:"updated_at"`
}

// ReturnItem is one order item + quantity within a return. Reason/Note are the
// RT-05 per-line return reason (empty Reason → the header reason applies).
type ReturnItem struct {
	ID          int64        `json:"id"`
	ReturnID    int64        `json:"return_id"`
	OrderID     int64        `json:"order_id"`
	OrderItemID int64        `json:"order_item_id"`
	Quantity    int          `json:"quantity"`
	Reason      ReturnReason `json:"reason,omitempty"`
	Note        string       `json:"note,omitempty"`
}

// ReturnStatusEvent is one append-only status-history row (RT-04). The audit
// trail recorded by InsertReturnStatusHistory, surfaced read-only so the return
// detail can render the real timeline instead of a status-derived one.
type ReturnStatusEvent struct {
	Status    string    `json:"status"`
	Note      string    `json:"note"`
	CreatedAt time.Time `json:"created_at"`
}

// ReturnItemInput is a requested item to return. Reason/Note are the RT-05
// per-line reason (optional; empty Reason falls back to the header reason).
type ReturnItemInput struct {
	OrderItemID int64
	Quantity    int
	Reason      ReturnReason
	Note        string
}

// ReturnInput is the validated input to CreateReturn.
type ReturnInput struct {
	OrderID     int64
	UserID      int64
	Reason      ReturnReason
	Description string
	Items       []ReturnItemInput
}

// ReturnableItem reports how much of an order item may still be returned.
type ReturnableItem struct {
	ItemID      int64 `json:"itemId"`
	MaxQuantity int   `json:"maxQuantity"`
}

// OrderActions is the server-computed eligibility block attached to an order
// DTO. The client renders CTAs from this — no client-side eligibility math.
type OrderActions struct {
	CanCancel       bool             `json:"canCancel"`
	CanReturn       bool             `json:"canReturn"`
	ReturnableUntil *time.Time       `json:"returnableUntil,omitempty"`
	ReturnableItems []ReturnableItem `json:"returnableItems"`
}

// ReturnRepository persists returns. Storage interface used only by returnService.
type ReturnRepository interface {
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
	InsertReturn(ctx context.Context, tx pgx.Tx, r Return) (Return, error)
	InsertReturnItem(ctx context.Context, tx pgx.Tx, it ReturnItem) (ReturnItem, error)
	InsertReturnStatusHistory(ctx context.Context, tx pgx.Tx, returnID int64, status, note string) error
	GetReturn(ctx context.Context, returnID int64) (Return, []ReturnItem, error)
	ListReturnsByUser(ctx context.Context, userID int64, limit, offset int) ([]Return, error)
	// ReturnedQtyByOrder returns order_item_id -> already-returned quantity.
	ReturnedQtyByOrder(ctx context.Context, orderID int64) (map[int64]int, error)
	// ListReturnsByProductIDs lists returns containing items from the given
	// products (seller scoping, Tranche 5a). Empty status = all statuses.
	ListReturnsByProductIDs(ctx context.Context, productIDs []int64, status string, limit, offset int) ([]Return, error)
	// ReturnProductIDs lists the product ids referenced by a return's items
	// (return_items → order_items, both order_schema; used to scope a seller's
	// approve/reject to returns that contain one of their products).
	ReturnProductIDs(ctx context.Context, returnID int64) ([]int64, error)
	// UpdateReturnStatus transitions a return's status within a tx.
	UpdateReturnStatus(ctx context.Context, tx pgx.Tx, returnID int64, status string) error
	// ListReturnStatusHistory reads the append-only status audit trail, oldest
	// first (RT-04).
	ListReturnStatusHistory(ctx context.Context, returnID int64) ([]ReturnStatusEvent, error)
}

// ReturnService is the public return surface. Kept separate from Service so the
// existing order Service mocks are untouched (same pattern as
// CheckoutSessionRepository).
type ReturnService interface {
	CreateReturn(ctx context.Context, in ReturnInput) (Return, []ReturnItem, error)
	GetReturn(ctx context.Context, userID, returnID int64) (Return, []ReturnItem, error)
	// GetReturnHistory returns the append-only status timeline for a return the
	// user owns (RT-04). Ownership-scoped: non-owners get ErrReturnNotFound.
	GetReturnHistory(ctx context.Context, userID, returnID int64) ([]ReturnStatusEvent, error)
	ListReturns(ctx context.Context, userID int64, limit, offset int) ([]Return, error)
	// ComputeActions derives the eligibility block for an order + its items.
	ComputeActions(ctx context.Context, o Order, items []OrderItem) (OrderActions, error)

	// ── Seller-side approval (Tranche 5a) ────────────────────────────────────
	// ListSellerReturns lists returns on the given (seller-owned) product ids.
	ListSellerReturns(ctx context.Context, productIDs []int64, status string, limit, offset int) ([]Return, error)
	// SellerApprove transitions a pending return → approved (refund amount was
	// recorded at creation). sellerProductIDs scopes the action to the seller's
	// own products: ErrReturnNotOwned if the return references none of them,
	// ErrReturnNotPending if not pending.
	SellerApprove(ctx context.Context, returnID int64, sellerProductIDs []int64) (Return, error)
	// SellerReject transitions a pending return → rejected (no refund), scoped to
	// the seller's products like SellerApprove.
	SellerReject(ctx context.Context, returnID int64, sellerProductIDs []int64, reasonCode, note string) (Return, error)
}

type returnService struct {
	orders  Repository
	returns ReturnRepository
	// outbox writes ecom.return.refunded.v1 in the same tx as the settlement
	// transition (RT-01, §4.5). nil disables refund settlement (SellerApprove
	// returns ErrOutboxNotConfigured) — required on the financial path.
	outbox outbox.Repository
	now    func() time.Time
}

// NewReturnService builds a ReturnService. orders provides read access to the
// referenced order; returns persists the request; outboxRepo (order_schema.outbox)
// carries the refund-settlement event to fin-svc — pass nil only in non-financial
// tests that never call SellerApprove.
func NewReturnService(orders Repository, returns ReturnRepository, outboxRepo outbox.Repository) ReturnService {
	return &returnService{orders: orders, returns: returns, outbox: outboxRepo, now: func() time.Time { return time.Now().UTC() }}
}

// ComputeActions: canCancel iff pre-shipment; canReturn iff delivered, within
// window, and at least one item still has returnable quantity.
func (s *returnService) ComputeActions(ctx context.Context, o Order, items []OrderItem) (OrderActions, error) {
	act := OrderActions{
		CanCancel:       o.Status == StatusPendingPayment || o.Status == StatusPaid,
		ReturnableItems: []ReturnableItem{},
	}
	if o.Status != StatusDelivered || o.DeliveredAt == nil {
		return act, nil
	}
	until := o.DeliveredAt.AddDate(0, 0, ReturnWindowDays)
	act.ReturnableUntil = &until

	returned, err := s.returns.ReturnedQtyByOrder(ctx, o.ID)
	if err != nil {
		return act, err
	}
	for _, it := range items {
		remaining := it.Qty - returned[it.ID]
		if remaining > 0 {
			act.ReturnableItems = append(act.ReturnableItems, ReturnableItem{ItemID: it.ID, MaxQuantity: remaining})
		}
	}
	act.CanReturn = !s.now().After(until) && len(act.ReturnableItems) > 0
	return act, nil
}

// validateReturnable checks the order is in a returnable state and returns its
// items indexed by id plus the already-returned quantities.
func (s *returnService) validateReturnable(ctx context.Context, in ReturnInput) (Order, []OrderItem, map[int64]int, error) {
	if !in.Reason.valid() {
		return Order{}, nil, nil, ErrInvalidReturnReason
	}
	o, items, err := s.orders.GetOrder(ctx, in.OrderID)
	if err != nil {
		return Order{}, nil, nil, err
	}
	if o.UserID != in.UserID {
		return Order{}, nil, nil, ErrOrderNotFound // do not leak existence to non-owners
	}
	if o.Status != StatusDelivered || o.DeliveredAt == nil {
		return Order{}, nil, nil, ErrOrderNotDelivered
	}
	if s.now().After(o.DeliveredAt.AddDate(0, 0, ReturnWindowDays)) {
		return Order{}, nil, nil, ErrReturnWindowExpired
	}
	returned, err := s.returns.ReturnedQtyByOrder(ctx, o.ID)
	if err != nil {
		return Order{}, nil, nil, err
	}
	return o, items, returned, nil
}

// resolveLines applies the default-all-items rule and validates each requested
// line against the order, returning the lines + the total refund amount.
func resolveLines(items []OrderItem, returned map[int64]int, requested []ReturnItemInput) ([]ReturnItemInput, int64, error) {
	byID := make(map[int64]OrderItem, len(items))
	for _, it := range items {
		byID[it.ID] = it
	}
	lines := requested
	if len(lines) == 0 { // full-order return of all remaining-returnable items
		for _, it := range items {
			if rem := it.Qty - returned[it.ID]; rem > 0 {
				lines = append(lines, ReturnItemInput{OrderItemID: it.ID, Quantity: rem})
			}
		}
	}
	if len(lines) == 0 {
		return nil, 0, ErrNoReturnableItems
	}
	var refundMinor int64
	for _, ri := range lines {
		oi, ok := byID[ri.OrderItemID]
		if !ok {
			return nil, 0, ErrItemNotInOrder
		}
		if ri.Quantity < 1 || ri.Quantity > oi.Qty-returned[oi.ID] {
			return nil, 0, ErrQuantityExceedsReturn
		}
		refundMinor += oi.UnitPriceMinor * int64(ri.Quantity)
	}
	return lines, refundMinor, nil
}

func (s *returnService) CreateReturn(ctx context.Context, in ReturnInput) (Return, []ReturnItem, error) {
	o, items, returned, err := s.validateReturnable(ctx, in)
	if err != nil {
		return Return{}, nil, err
	}
	reqItems, refundMinor, err := resolveLines(items, returned, in.Items)
	if err != nil {
		return Return{}, nil, err
	}
	currency := o.Currency

	var (
		out      Return
		outItems []ReturnItem
	)
	err = s.returns.WithTx(ctx, func(tx pgx.Tx) error {
		rec, e := s.returns.InsertReturn(ctx, tx, Return{
			OrderID:           o.ID,
			UserID:            in.UserID,
			Status:            ReturnPending,
			Reason:            in.Reason,
			Description:       in.Description,
			RefundAmountMinor: refundMinor,
			RefundCurrency:    currency,
		})
		if e != nil {
			return e
		}
		for _, ri := range reqItems {
			// RT-05: per-line reason; empty falls back to the header reason. A
			// supplied line reason must be a valid enum value.
			lineReason := ri.Reason
			if lineReason == "" {
				lineReason = in.Reason
			} else if !lineReason.valid() {
				return ErrInvalidReturnReason
			}
			item, e := s.returns.InsertReturnItem(ctx, tx, ReturnItem{
				ReturnID:    rec.ID,
				OrderID:     o.ID,
				OrderItemID: ri.OrderItemID,
				Quantity:    ri.Quantity,
				Reason:      lineReason,
				Note:        ri.Note,
			})
			if e != nil {
				return e
			}
			outItems = append(outItems, item)
		}
		if e := s.returns.InsertReturnStatusHistory(ctx, tx, rec.ID, string(ReturnPending), "submitted"); e != nil {
			return e
		}
		out = rec
		return nil
	})
	if err != nil {
		if errors.Is(err, ErrReturnAlreadyExists) {
			return Return{}, nil, ErrReturnAlreadyExists
		}
		return Return{}, nil, fmt.Errorf("order.returns: create: %w", err)
	}
	return out, outItems, nil
}

func (s *returnService) GetReturn(ctx context.Context, userID, returnID int64) (Return, []ReturnItem, error) {
	r, items, err := s.returns.GetReturn(ctx, returnID)
	if err != nil {
		return Return{}, nil, err
	}
	if r.UserID != userID {
		return Return{}, nil, ErrReturnNotFound // ownership scoping
	}
	return r, items, nil
}

// GetReturnHistory returns the status audit trail for a return the user owns
// (RT-04). Reuses GetReturn's ownership check so non-owners get ErrReturnNotFound.
func (s *returnService) GetReturnHistory(ctx context.Context, userID, returnID int64) ([]ReturnStatusEvent, error) {
	r, _, err := s.returns.GetReturn(ctx, returnID)
	if err != nil {
		return nil, err
	}
	if r.UserID != userID {
		return nil, ErrReturnNotFound // ownership scoping
	}
	return s.returns.ListReturnStatusHistory(ctx, returnID)
}

func (s *returnService) ListReturns(ctx context.Context, userID int64, limit, offset int) ([]Return, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}
	return s.returns.ListReturnsByUser(ctx, userID, limit, offset)
}

// ── Seller-side approval (Tranche 5a) ────────────────────────────────────────

func (s *returnService) ListSellerReturns(ctx context.Context, productIDs []int64, status string, limit, offset int) ([]Return, error) {
	if len(productIDs) == 0 {
		return []Return{}, nil
	}
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}
	return s.returns.ListReturnsByProductIDs(ctx, productIDs, status, limit, offset)
}

// returnRefundedPayload is the ecom.return.refunded.v1 body. The fin-svc
// internal/refund consumer mints RefundAmountMinor as coin (1:1 peg) to user_id's
// wallet; it derives the coin currency from its own config (the fiat Currency here
// is for audit/display). Market drives the per-market coin code if ever needed.
type returnRefundedPayload struct {
	ReturnID          int64  `json:"return_id"`
	OrderID           int64  `json:"order_id"`
	UserID            int64  `json:"user_id"`
	RefundAmountMinor int64  `json:"refund_amount_minor"`
	Currency          string `json:"currency"` // fiat (the order's currency)
	Market            string `json:"market"`
}

// SellerApprove approves AND settles a pending return in one tx (RT-01): it
// transitions pending → approved → refunded, records both history rows, and writes
// ecom.return.refunded.v1 to the outbox (§4.5) so fin-svc mints the refund as coin.
// Atomic ⇒ no stuck "approved" state; idempotent ⇒ the pending-status guard runs it
// once and the outbox key (return:refunded:<id>) + the fin ledger key dedupe.
func (s *returnService) SellerApprove(ctx context.Context, returnID int64, sellerProductIDs []int64) (Return, error) {
	if s.outbox == nil {
		return Return{}, ErrOutboxNotConfigured
	}
	rec, _, err := s.returns.GetReturn(ctx, returnID)
	if err != nil {
		return Return{}, err
	}
	owns, err := s.returnOwnedBySeller(ctx, returnID, sellerProductIDs)
	if err != nil {
		return Return{}, err
	}
	if !owns {
		return Return{}, ErrReturnNotOwned // do not leak existence to other sellers
	}
	if rec.Status != ReturnPending {
		return Return{}, ErrReturnNotPending
	}

	// The order supplies Market for the event (the refund amount + fiat currency are
	// already snapshotted on the return at CreateReturn).
	o, _, err := s.orders.GetOrder(ctx, rec.OrderID)
	if err != nil {
		return Return{}, fmt.Errorf("order.returns: settle get order %d: %w", rec.OrderID, err)
	}
	payload, err := json.Marshal(returnRefundedPayload{
		ReturnID:          rec.ID,
		OrderID:           rec.OrderID,
		UserID:            rec.UserID,
		RefundAmountMinor: rec.RefundAmountMinor,
		Currency:          rec.RefundCurrency,
		Market:            o.Market,
	})
	if err != nil {
		return Return{}, fmt.Errorf("order.returns: marshal refunded payload: %w", err)
	}
	idemKey := fmt.Sprintf("return:refunded:%d", rec.ID)

	err = s.returns.WithTx(ctx, func(tx pgx.Tx) error {
		if e := s.returns.UpdateReturnStatus(ctx, tx, returnID, string(ReturnApproved)); e != nil {
			return e
		}
		if e := s.returns.InsertReturnStatusHistory(ctx, tx, returnID, string(ReturnApproved), "seller approved"); e != nil {
			return e
		}
		if e := s.returns.UpdateReturnStatus(ctx, tx, returnID, string(ReturnRefunded)); e != nil {
			return e
		}
		if e := s.returns.InsertReturnStatusHistory(ctx, tx, returnID, string(ReturnRefunded), "refund issued as Mopro Coin"); e != nil {
			return e
		}
		return s.outbox.Insert(ctx, tx, outbox.Row{
			Aggregate:      "return",
			EventType:      "ecom.return.refunded.v1",
			Payload:        json.RawMessage(payload),
			IdempotencyKey: idemKey,
			Market:         o.Market,
			Currency:       rec.RefundCurrency,
		})
	})
	if err != nil {
		return Return{}, err
	}
	rec.Status = ReturnRefunded
	return rec, nil
}

func (s *returnService) SellerReject(ctx context.Context, returnID int64, sellerProductIDs []int64, reasonCode, note string) (Return, error) {
	msg := "seller rejected: " + reasonCode
	if note != "" {
		msg += " — " + note
	}
	return s.transition(ctx, returnID, sellerProductIDs, string(ReturnRejected), msg)
}

// transition verifies the return belongs to one of the seller's products, then
// guards pending→{approved,rejected} and records the status history.
func (s *returnService) transition(ctx context.Context, returnID int64, sellerProductIDs []int64, status, note string) (Return, error) {
	rec, _, err := s.returns.GetReturn(ctx, returnID)
	if err != nil {
		return Return{}, err
	}
	owns, err := s.returnOwnedBySeller(ctx, returnID, sellerProductIDs)
	if err != nil {
		return Return{}, err
	}
	if !owns {
		return Return{}, ErrReturnNotOwned // do not leak existence to other sellers
	}
	if rec.Status != ReturnPending {
		return Return{}, ErrReturnNotPending
	}
	err = s.returns.WithTx(ctx, func(tx pgx.Tx) error {
		if e := s.returns.UpdateReturnStatus(ctx, tx, returnID, status); e != nil {
			return e
		}
		return s.returns.InsertReturnStatusHistory(ctx, tx, returnID, status, note)
	})
	if err != nil {
		return Return{}, err
	}
	rec.Status = ReturnStatus(status)
	return rec, nil
}

// returnOwnedBySeller reports whether the return references at least one of the
// seller's products.
func (s *returnService) returnOwnedBySeller(ctx context.Context, returnID int64, sellerProductIDs []int64) (bool, error) {
	if len(sellerProductIDs) == 0 {
		return false, nil
	}
	pids, err := s.returns.ReturnProductIDs(ctx, returnID)
	if err != nil {
		return false, err
	}
	owned := make(map[int64]struct{}, len(sellerProductIDs))
	for _, id := range sellerProductIDs {
		owned[id] = struct{}{}
	}
	for _, id := range pids {
		if _, ok := owned[id]; ok {
			return true, nil
		}
	}
	return false, nil
}
