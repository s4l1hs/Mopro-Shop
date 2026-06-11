package order

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/payment"
)

// ErrPSPNotConfigured is returned when InitiateCheckout is called on a Service
// constructed with NewService (no PSP). Use NewServiceFull to enable PSP integration.
var ErrPSPNotConfigured = errors.New("order: PSP not configured; use NewServiceFull")

// ErrCheckoutSessionRequired is returned when SessionID is empty.
var ErrCheckoutSessionRequired = errors.New("order: SessionID (Idempotency-Key) is required for checkout")

// InitiateCheckout is the v8 saga:
//  1. Idempotency: return existing session if already created.
//  2. Get cart → build per-seller OrderItem groups.
//  3. DB transaction: insert one Order per seller + all items + the CheckoutSession (pending).
//  4. Call PSP: InitiatePayment for the total amount.
//  5. On success: update session to psp_initiated with provider_ref.
//  6. On failure: cancel all orders + update session to failed, return error.
func (s *orderService) InitiateCheckout(ctx context.Context, req InitiateCheckoutRequest) (InitiateCheckoutResponse, error) { //nolint:gocyclo // multi-step checkout saga; complexity is inherent
	// Disk panic guard: fail-open so a Redis outage never blocks checkout.
	if s.diskChecker != nil {
		checkCtx, cancel := context.WithTimeout(ctx, 100*time.Millisecond)
		defer cancel()
		if s.diskChecker.IsDiskPanic(checkCtx) {
			return InitiateCheckoutResponse{}, ErrDiskPanic
		}
	}

	if s.psp == nil {
		return InitiateCheckoutResponse{}, ErrPSPNotConfigured
	}
	if req.SessionID == "" {
		return InitiateCheckoutResponse{}, ErrCheckoutSessionRequired
	}
	if s.sessionRepo == nil {
		return InitiateCheckoutResponse{}, fmt.Errorf("order: CheckoutSessionRepository not configured")
	}

	// 1. Idempotency check.
	existing, err := s.sessionRepo.FindCheckoutSessionByID(ctx, req.SessionID)
	if err == nil {
		// Re-assemble orders for the response (best-effort).
		orders := make([]Order, 0, len(existing.OrderIDs))
		for _, oid := range existing.OrderIDs {
			o, _, oErr := s.repo.GetOrder(ctx, oid)
			if oErr == nil {
				orders = append(orders, o)
			}
		}
		return InitiateCheckoutResponse{
			SessionID: existing.ID,
			Orders:    orders,
		}, nil
	}
	if !errors.Is(err, ErrCheckoutSessionNotFound) {
		return InitiateCheckoutResponse{}, fmt.Errorf("order: saga idempotency check: %w", err)
	}

	// 2. Get cart.
	cartState, err := s.cart.GetCart(ctx, req.UserID)
	if err != nil {
		return InitiateCheckoutResponse{}, fmt.Errorf("order: saga get cart: %w", err)
	}
	if len(cartState.Items) == 0 {
		return InitiateCheckoutResponse{}, ErrEmptyCart
	}

	market := req.Market
	if market == "" {
		market = s.defaultMarket
	}

	// 3. Build per-seller groups with commission snapshots.
	type sellerGroup struct {
		sellerID int64
		items    []OrderItem
		subtotal int64 // pre-discount Σ(list_unit×qty)
		discount int64 // Σ(list−discounted)×qty (seller-funded basket discount, CT-09)
		currency string
	}
	groupsBySellerID := make(map[int64]*sellerGroup)
	var totalMinor int64 // charged total across all sellers (discounted)
	var currency string

	for _, ci := range cartState.Items {
		v, vErr := s.catalog.GetVariantByID(ctx, ci.VariantID)
		if vErr != nil {
			return InitiateCheckoutResponse{}, fmt.Errorf("order: saga get variant %d: %w", ci.VariantID, vErr)
		}
		comm, cErr := s.catalog.GetCommissionForCategory(ctx, market, v.CategoryID)
		if cErr != nil {
			return InitiateCheckoutResponse{}, fmt.Errorf("order: saga get commission variant %d: %w", ci.VariantID, cErr)
		}

		// Per-unit basket discount → charged unit = snapshot unit_price_minor (CT-09).
		pct := basketPctOf(v.BasketDiscountPct)
		discUnit := DiscountedUnitMinor(v.PriceMinor, pct)
		listGross := v.PriceMinor * int64(ci.Qty)
		gross := discUnit * int64(ci.Qty)
		commAmt := gross * int64(comm.CommissionPctBps) / 10000
		kdvAmt := commAmt * int64(comm.KdvPctBps) / 10000
		sellerNet := gross - commAmt - kdvAmt

		item := OrderItem{
			VariantID:             ci.VariantID,
			SellerID:              v.SellerID,
			CategoryID:            v.CategoryID,
			Qty:                   ci.Qty,
			UnitPriceMinor:        discUnit,
			ListUnitPriceMinor:    v.PriceMinor,
			BasketDiscountPct:     pct,
			UnitPriceCurrency:     v.PriceCurrency,
			CommissionPctBps:      comm.CommissionPctBps,
			KdvPctBps:             comm.KdvPctBps,
			CommissionAmountMinor: commAmt,
			KdvAmountMinor:        kdvAmt,
			SellerNetMinor:        sellerNet,
		}

		g := groupsBySellerID[v.SellerID]
		if g == nil {
			g = &sellerGroup{sellerID: v.SellerID, currency: v.PriceCurrency}
			groupsBySellerID[v.SellerID] = g
		}
		g.items = append(g.items, item)
		g.subtotal += listGross
		g.discount += listGross - gross
		totalMinor += gross
		if currency == "" {
			currency = v.PriceCurrency
		}
	}
	if req.Currency != "" {
		currency = req.Currency
	}

	// 4. DB transaction: insert orders + items + checkout session.
	var createdOrders []Order
	var orderIDs []int64
	session := CheckoutSession{
		ID:            req.SessionID,
		UserID:        req.UserID,
		ReservationID: req.ReservationID,
		Status:        CheckoutSessionPending,
		AmountMinor:   totalMinor,
		Currency:      currency,
		ExpiresAt:     time.Now().Add(30 * time.Minute).UTC(),
	}

	if err := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		for _, g := range groupsBySellerID {
			// One idempotency key per seller within this checkout session.
			idemKey := fmt.Sprintf("%s:seller_%d", req.SessionID, g.sellerID)
			o := Order{
				UserID:            req.UserID,
				SellerID:          g.sellerID,
				CheckoutSessionID: req.SessionID,
				Status:            StatusPendingPayment,
				SubtotalMinor:     g.subtotal,
				ShippingMinor:     0,
				ShippingPayer:     "buyer",
				DiscountMinor:     g.discount,
				TotalMinor:        g.subtotal - g.discount,
				Currency:          g.currency,
				Market:            market,
				CashbackEligible:  true,
				CashbackCurrency:  s.cashbackCurrency,
				IdempotencyKey:    idemKey,
			}
			created, txErr := s.repo.InsertOrder(ctx, tx, o)
			if txErr != nil {
				return txErr
			}
			for _, item := range g.items {
				item.OrderID = created.ID
				if _, txErr = s.repo.InsertOrderItem(ctx, tx, item); txErr != nil {
					return txErr
				}
			}
			createdOrders = append(createdOrders, created)
			orderIDs = append(orderIDs, created.ID)
		}

		session.OrderIDs = orderIDs
		var sessErr error
		session, sessErr = s.sessionRepo.InsertCheckoutSession(ctx, tx, session)
		return sessErr
	}); err != nil {
		return InitiateCheckoutResponse{}, fmt.Errorf("order: saga persist: %w", err)
	}

	// 5. Call PSP (outside the DB transaction to avoid holding a lock during HTTP).
	// Use the first order's ID as the PSP order reference (single-payment constraint).
	var primaryOrderID int64
	if len(orderIDs) > 0 {
		primaryOrderID = orderIDs[0]
	}
	pspResp, pspErr := s.psp.InitiatePayment(ctx, payment.InitiatePaymentRequest{
		OrderID:        primaryOrderID,
		AmountMinor:    totalMinor,
		Currency:       currency,
		IdempotencyKey: req.SessionID, // invoice_id == session_id
		BuyerName:      req.BuyerName,
		BuyerSurname:   req.BuyerSurname,
		BuyerEmail:     req.BuyerEmail,
		Market:         market,
		ReturnURL:      req.ReturnURL,
	})

	if pspErr != nil {
		// Saga compensation: cancel all orders and mark session failed.
		now := time.Now().UTC()
		for _, oid := range orderIDs {
			if cancelErr := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
				return s.repo.UpdateStatus(ctx, tx, oid, StatusCancelled, now)
			}); cancelErr != nil {
				slog.Error("order: saga compensation cancel failed",
					"order_id", oid, "err", cancelErr)
			}
		}
		if updErr := s.sessionRepo.UpdateCheckoutSession(ctx, req.SessionID, CheckoutSessionFailed, ""); updErr != nil {
			slog.Error("order: saga compensation session update failed",
				"session_id", req.SessionID, "err", updErr)
		}
		return InitiateCheckoutResponse{}, fmt.Errorf("order: saga PSP initiate: %w", pspErr)
	}

	// 6. PSP succeeded: update session to psp_initiated.
	if updErr := s.sessionRepo.UpdateCheckoutSession(ctx, req.SessionID, CheckoutSessionPSPInitiated, pspResp.ProviderRef); updErr != nil {
		// Non-fatal: session is still pending; the webhook will eventually mark it completed.
		slog.Warn("order: saga session update psp_initiated failed (non-fatal)",
			"session_id", req.SessionID, "err", updErr)
	}

	return InitiateCheckoutResponse{
		SessionID:   req.SessionID,
		ThreeDSHTML: pspResp.ThreeDSHTML,
		ThreeDSURL:  pspResp.ThreeDSURL,
		Orders:      createdOrders,
	}, nil
}
