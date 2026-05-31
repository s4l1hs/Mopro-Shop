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
	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/pkg/mediaurl"
	"github.com/mopro/platform/pkg/metrics"
)

type orderService struct {
	repo             Repository
	sessionRepo      CheckoutSessionRepository // nil for legacy NewService
	cart             cart.Service
	catalog          catalog.Service
	outbox           outbox.Repository
	defaultMarket    string
	cashbackCurrency string                   // e.g. "TRY_COIN" for TR; read from env at startup
	psp              payment.Service          // nil for legacy NewService (no PSP call in Checkout)
	diskChecker      DiskPressureChecker      // nil disables disk panic check
	biz              *metrics.BusinessMetrics // nil disables business KPI counters
}

// NewService constructs an order Service for the legacy single-order checkout flow.
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

// NewServiceFull constructs an order Service with PSP integration for InitiateCheckout.
// diskChecker is optional (nil disables the disk panic guard in InitiateCheckout).
// biz is optional (nil disables business KPI metrics).
func NewServiceFull(
	repo Repository,
	sessionRepo CheckoutSessionRepository,
	cartSvc cart.Service,
	catalogSvc catalog.Service,
	outboxRepo outbox.Repository,
	defaultMarket string,
	cashbackCurrency string,
	psp payment.Service,
	diskChecker DiskPressureChecker,
	biz *metrics.BusinessMetrics,
) Service {
	return &orderService{
		repo:             repo,
		sessionRepo:      sessionRepo,
		cart:             cartSvc,
		catalog:          catalogSvc,
		outbox:           outboxRepo,
		defaultMarket:    defaultMarket,
		cashbackCurrency: cashbackCurrency,
		psp:              psp,
		diskChecker:      diskChecker,
		biz:              biz,
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
	// Pre-fetch current status for from→to metrics label. Best-effort: uses
	// "unknown" when the fetch fails. No transaction needed for a metric label.
	fromStatus := OrderStatus("unknown")
	if s.biz != nil {
		if o, _, err := s.repo.GetOrder(ctx, orderID); err == nil {
			fromStatus = o.Status
		}
	}
	now := time.Now().UTC()
	if err := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		return s.repo.UpdateStatus(ctx, tx, orderID, status, now)
	}); err != nil {
		return err
	}
	s.biz.IncOrderStatusTransition("core-svc", string(fromStatus), string(status))
	return nil
}

// CancelOrder transitions an order to cancelled. Only valid from pending_payment or paid.
// reason is logged for audit purposes but not persisted in v1 (no cancellation_reason column yet).
func (s *orderService) CancelOrder(ctx context.Context, orderID int64, reason string) error {
	o, _, err := s.repo.GetOrder(ctx, orderID)
	if err != nil {
		return err
	}
	// Idempotent: re-cancelling an already-cancelled order is a no-op success,
	// not an error (§3.2). Concurrent double-submits converge here.
	if o.Status == StatusCancelled {
		return nil
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

	// Resolve product snapshot from the first item for the cashback plan's display fields.
	var productID int64
	var productTitle, productImageURL string
	if len(items) > 0 {
		v, vErr := s.catalog.GetVariantByID(ctx, items[0].VariantID)
		if vErr == nil {
			productID = v.ProductID
			_, _, translations, tErr := s.catalog.GetByID(ctx, v.ProductID)
			if tErr == nil {
				for _, t := range translations {
					if productTitle == "" {
						productTitle = t.Title
					}
					if t.Locale == "tr-TR" || t.Locale == o.Market {
						productTitle = t.Title
					}
				}
			}
			if len(v.ImageKeys) > 0 {
				productImageURL = mediaurl.CDNUrl(v.ImageKeys[0])
			}
		}
		// Catalog lookup failure is non-fatal: plan still created, title shows as "Sipariş #N".
		if vErr != nil {
			slog.Warn("order: catalog lookup for product enrichment failed",
				"order_id", orderID, "variant_id", items[0].VariantID, "err", vErr)
		}
	}

	payload, err := json.Marshal(buildDeliveredPayload(o, items, deliveredAt, productID, productTitle, productImageURL))
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
	// Phase 4.4a: product snapshot from first item (omitempty for backward compat).
	ProductID       int64  `json:"product_id,omitempty"`
	ProductTitle    string `json:"product_title,omitempty"`
	ProductImageURL string `json:"product_image_url,omitempty"`
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

// MarkPaid transitions an order from pending_payment → paid and emits ecom.order.paid.v1.
// Called by the Sipay webhook CaptureFinalizer. Idempotent: returns nil if already paid.
// The payload includes seller_id, shipping_minor and per-item commission snapshots so
// the fin-svc orderledger consumer can post the balanced ledger entry without querying
// postgres-ecom (CLAUDE.md §3.2: fin-svc may only reach postgres-ledger).
func (s *orderService) MarkPaid(ctx context.Context, orderID int64) error {
	o, items, err := s.repo.GetOrder(ctx, orderID)
	if err != nil {
		return err
	}
	if o.Status == StatusPaid {
		return nil // idempotent
	}
	if err := ValidTransition(o.Status, StatusPaid); err != nil {
		return err
	}
	now := time.Now().UTC()
	payload, _ := json.Marshal(buildPaidPayload(o, items, now))
	return s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		if err := s.repo.UpdateStatus(ctx, tx, orderID, StatusPaid, now); err != nil {
			return err
		}
		return s.outbox.Insert(ctx, tx, outbox.Row{
			Aggregate:      "order",
			EventType:      "ecom.order.paid.v1",
			Payload:        json.RawMessage(payload),
			IdempotencyKey: fmt.Sprintf("order:paid:order_%d", orderID),
			Market:         o.Market,
			Currency:       o.Currency,
		})
	})
}

// buildPaidPayload serialises the enriched ecom.order.paid.v1 payload.
// Items carry frozen commission snapshots so fin-svc can post the capture ledger entry
// without a cross-service call to postgres-ecom.
func buildPaidPayload(o Order, items []OrderItem, paidAt time.Time) paidPayload {
	its := make([]paidItemPayload, len(items))
	for i, it := range items {
		its[i] = paidItemPayload{
			VariantID:             it.VariantID,
			SellerID:              it.SellerID,
			Qty:                   it.Qty,
			UnitPriceMinor:        it.UnitPriceMinor,
			CommissionPctBps:      it.CommissionPctBps,
			KdvPctBps:             it.KdvPctBps,
			CommissionAmountMinor: it.CommissionAmountMinor,
			KdvAmountMinor:        it.KdvAmountMinor,
			SellerNetMinor:        it.SellerNetMinor,
		}
	}
	return paidPayload{
		OrderID:       o.ID,
		UserID:        o.UserID,
		SellerID:      o.SellerID,
		PaidAt:        paidAt,
		AmountMinor:   o.TotalMinor,
		ShippingMinor: o.ShippingMinor,
		Currency:      o.Currency,
		Market:        o.Market,
		Items:         its,
	}
}

type paidPayload struct {
	OrderID       int64             `json:"order_id"`
	UserID        int64             `json:"user_id"`
	SellerID      int64             `json:"seller_id"`
	PaidAt        time.Time         `json:"paid_at"`
	AmountMinor   int64             `json:"amount_minor"`
	ShippingMinor int64             `json:"shipping_minor"`
	Currency      string            `json:"currency"`
	Market        string            `json:"market"`
	Items         []paidItemPayload `json:"items"`
}

type paidItemPayload struct {
	VariantID             int64 `json:"variant_id"`
	SellerID              int64 `json:"seller_id"`
	Qty                   int   `json:"qty"`
	UnitPriceMinor        int64 `json:"unit_price_minor"`
	CommissionPctBps      int   `json:"commission_pct_bps"`
	KdvPctBps             int   `json:"kdv_pct_bps"`
	CommissionAmountMinor int64 `json:"commission_amount_minor"`
	KdvAmountMinor        int64 `json:"kdv_amount_minor"`
	SellerNetMinor        int64 `json:"seller_net_minor"`
}

// buildDeliveredPayload serialises the order + items into the event payload.
// productID/productTitle/productImageURL come from a pre-resolved catalog lookup.
func buildDeliveredPayload(
	o Order,
	items []OrderItem,
	deliveredAt time.Time,
	productID int64,
	productTitle string,
	productImageURL string,
) deliveredPayload {
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
		OrderID:         o.ID,
		UserID:          o.UserID,
		DeliveredAt:     deliveredAt.UTC(),
		Market:          o.Market,
		Currency:        o.Currency,
		Items:           its,
		ProductID:       productID,
		ProductTitle:    productTitle,
		ProductImageURL: productImageURL,
	}
}
