package order

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/outbox"
)

type orderService struct {
	repo             Repository
	cart             cart.Service
	catalog          catalog.Service
	outbox           outbox.Repository
	defaultMarket    string
	cashbackCurrency string // e.g. "TRY_COIN" for TR; read from env at startup
}

// NewService constructs an order Service.
// cashbackCurrency should come from env DEFAULT_CASHBACK_CURRENCY (e.g. "TRY_COIN").
func NewService(
	repo Repository,
	cartSvc cart.Service,
	catalogSvc catalog.Service,
	outboxRepo outbox.Repository,
	defaultMarket string,
	cashbackCurrency string,
) Service {
	return &orderService{
		repo:             repo,
		cart:             cartSvc,
		catalog:          catalogSvc,
		outbox:           outboxRepo,
		defaultMarket:    defaultMarket,
		cashbackCurrency: cashbackCurrency,
	}
}

// Checkout creates an order from the user's active cart.
// It reads commission snapshots from ref_schema at order time and freezes them.
// Idempotent: returns the existing order if IdempotencyKey already exists.
func (s *orderService) Checkout(ctx context.Context, req CheckoutRequest) (Order, []OrderItem, error) { //nolint:gocyclo,cyclop
	// 1. Idempotency check
	existing, err := s.repo.FindByIdempotencyKey(ctx, req.IdempotencyKey)
	if err == nil {
		items, err2 := s.repo.GetOrderItems(ctx, existing.ID)
		if err2 != nil {
			return Order{}, nil, fmt.Errorf("order: checkout idempotency fetch items: %w", err2)
		}
		return existing, items, nil
	}
	if !errors.Is(err, ErrOrderNotFound) {
		return Order{}, nil, fmt.Errorf("order: checkout idempotency lookup: %w", err)
	}

	// 2. Get cart items
	cartState, err := s.cart.GetCart(ctx, req.UserID)
	if err != nil {
		return Order{}, nil, fmt.Errorf("order: checkout get cart: %w", err)
	}
	if len(cartState.Items) == 0 {
		return Order{}, nil, ErrEmptyCart
	}

	market := req.Market
	if market == "" {
		market = s.defaultMarket
	}

	// 3. Build order items with commission snapshots (frozen at order time)
	items := make([]OrderItem, 0, len(cartState.Items))
	var subtotal int64
	var currency string
	for _, ci := range cartState.Items {
		v, err := s.catalog.GetVariantByID(ctx, ci.VariantID)
		if err != nil {
			return Order{}, nil, fmt.Errorf("order: checkout get variant %d: %w", ci.VariantID, err)
		}
		comm, err := s.catalog.GetCommissionForCategory(ctx, market, v.CategoryID)
		if err != nil {
			return Order{}, nil, fmt.Errorf("order: checkout get commission variant %d: %w", ci.VariantID, err)
		}

		gross := v.PriceMinor * int64(ci.Qty)
		// Integer arithmetic — NEVER float (CLAUDE.md § 4.6 + § 10.7)
		commAmt := gross * int64(comm.CommissionPctBps) / 10000
		kdvAmt := commAmt * int64(comm.KdvPctBps) / 10000
		sellerNet := gross - commAmt - kdvAmt

		items = append(items, OrderItem{
			VariantID:             ci.VariantID,
			SellerID:              v.SellerID,
			CategoryID:            v.CategoryID,
			Qty:                   ci.Qty,
			UnitPriceMinor:        v.PriceMinor,
			UnitPriceCurrency:     v.PriceCurrency,
			CommissionPctBps:      comm.CommissionPctBps,
			KdvPctBps:             comm.KdvPctBps,
			CommissionAmountMinor: commAmt,
			KdvAmountMinor:        kdvAmt,
			SellerNetMinor:        sellerNet,
		})
		subtotal += gross
		if currency == "" {
			currency = v.PriceCurrency
		}
	}
	if req.Currency != "" {
		currency = req.Currency
	}

	o := Order{
		UserID:           req.UserID,
		Status:           StatusPendingPayment,
		SubtotalMinor:    subtotal,
		ShippingMinor:    0,
		ShippingPayer:    "buyer",
		TotalMinor:       subtotal,
		Currency:         currency,
		Market:           market,
		CashbackEligible: true,
		CashbackCurrency: s.cashbackCurrency,
		IdempotencyKey:   req.IdempotencyKey,
	}

	// 4. Persist order + items in a single DB transaction
	var createdOrder Order
	var createdItems []OrderItem
	if err := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		var txErr error
		createdOrder, txErr = s.repo.InsertOrder(ctx, tx, o)
		if txErr != nil {
			return txErr
		}
		for _, item := range items {
			item.OrderID = createdOrder.ID
			inserted, txErr := s.repo.InsertOrderItem(ctx, tx, item)
			if txErr != nil {
				return txErr
			}
			createdItems = append(createdItems, inserted)
		}
		return nil
	}); err != nil {
		return Order{}, nil, fmt.Errorf("order: checkout persist: %w", err)
	}

	// 5. Commit reservation (best-effort; stock is already decremented by TryReserve)
	if req.ReservationID != "" {
		if commitErr := s.cart.CommitReservation(ctx, req.ReservationID); commitErr != nil {
			slog.Warn("order: CommitReservation failed (best-effort)",
				"reservation_id", req.ReservationID, "err", commitErr)
		}
	}

	return createdOrder, createdItems, nil
}

func (s *orderService) GetOrder(ctx context.Context, orderID int64) (Order, []OrderItem, error) {
	return s.repo.GetOrder(ctx, orderID)
}

func (s *orderService) ListOrders(ctx context.Context, userID int64) ([]Order, error) {
	return s.repo.ListOrders(ctx, userID)
}

func (s *orderService) UpdateStatus(ctx context.Context, orderID int64, status OrderStatus) error {
	now := time.Now().UTC()
	return s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		return s.repo.UpdateStatus(ctx, tx, orderID, status, now)
	})
}

// CancelOrder transitions an order to cancelled. Only valid from pending_payment or paid.
// reason is logged for audit purposes but not persisted in v1 (no cancellation_reason column yet).
func (s *orderService) CancelOrder(ctx context.Context, orderID int64, reason string) error {
	o, _, err := s.repo.GetOrder(ctx, orderID)
	if err != nil {
		return err
	}
	if o.Status != StatusPendingPayment && o.Status != StatusPaid {
		return fmt.Errorf("%w: cannot cancel order in status %q", ErrInvalidTransition, o.Status)
	}
	slog.Info("order: cancelling", "order_id", orderID, "from_status", o.Status, "reason", reason)
	now := time.Now().UTC()
	return s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		return s.repo.UpdateStatus(ctx, tx, orderID, StatusCancelled, now)
	})
}

// MarkDelivered sets status='delivered', records delivered_at, and publishes
// ecom.order.delivered.v1 to the outbox within the same transaction.
// This event triggers both the cashback engine and seller payout engine.
func (s *orderService) MarkDelivered(ctx context.Context, orderID int64, deliveredAt time.Time) error {
	o, items, err := s.repo.GetOrder(ctx, orderID)
	if err != nil {
		return err
	}
	if o.Status == StatusDelivered {
		return nil // idempotent
	}

	payload, err := json.Marshal(buildDeliveredPayload(o, items, deliveredAt))
	if err != nil {
		return fmt.Errorf("order: marshal delivered payload: %w", err)
	}

	idempKey := fmt.Sprintf("order:delivered:order_%d", orderID)

	return s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		if err := s.repo.SetDelivered(ctx, tx, orderID, deliveredAt); err != nil {
			return err
		}
		return s.outbox.Insert(ctx, tx, outbox.Row{
			Aggregate:      "order",
			EventType:      "ecom.order.delivered.v1",
			Payload:        json.RawMessage(payload),
			IdempotencyKey: idempKey,
			Market:         o.Market,
			Currency:       o.Currency,
		})
	})
}

// ── event payload types ───────────────────────────────────────────────────────

type deliveredPayload struct {
	OrderID     int64                  `json:"order_id"`
	UserID      int64                  `json:"user_id"`
	DeliveredAt time.Time              `json:"delivered_at"`
	Market      string                 `json:"market"`
	Currency    string                 `json:"currency"`
	Items       []deliveredItemPayload `json:"items"`
}

type deliveredItemPayload struct {
	VariantID             int64 `json:"variant_id"`
	SellerID              int64 `json:"seller_id"`
	CategoryID            int64 `json:"category_id"`
	Qty                   int   `json:"qty"`
	UnitPriceMinor        int64 `json:"unit_price_minor"`
	CommissionPctBps      int   `json:"commission_pct_bps"`
	KdvPctBps             int   `json:"kdv_pct_bps"`
	CommissionAmountMinor int64 `json:"commission_amount_minor"`
	KdvAmountMinor        int64 `json:"kdv_amount_minor"`
	SellerNetMinor        int64 `json:"seller_net_minor"`
}

func buildDeliveredPayload(o Order, items []OrderItem, deliveredAt time.Time) deliveredPayload {
	its := make([]deliveredItemPayload, len(items))
	for i, it := range items {
		its[i] = deliveredItemPayload{
			VariantID:             it.VariantID,
			SellerID:              it.SellerID,
			CategoryID:            it.CategoryID,
			Qty:                   it.Qty,
			UnitPriceMinor:        it.UnitPriceMinor,
			CommissionPctBps:      it.CommissionPctBps,
			KdvPctBps:             it.KdvPctBps,
			CommissionAmountMinor: it.CommissionAmountMinor,
			KdvAmountMinor:        it.KdvAmountMinor,
			SellerNetMinor:        it.SellerNetMinor,
		}
	}
	return deliveredPayload{
		OrderID:     o.ID,
		UserID:      o.UserID,
		DeliveredAt: deliveredAt.UTC(),
		Market:      o.Market,
		Currency:    o.Currency,
		Items:       its,
	}
}
