package cashback

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/mopro/platform/internal/eventbus"
)

const (
	// TopicOrderDelivered is the Redis Streams topic produced by core-svc order.MarkDelivered.
	TopicOrderDelivered = "ecom.order.delivered.v1"
	// ConsumerGroup is the cashback engine's durable consumer group name.
	ConsumerGroup = "cashback-engine"
)

// orderDeliveredPayload matches the JSON written by order.buildDeliveredPayload.
type orderDeliveredPayload struct {
	OrderID     int64     `json:"order_id"`
	UserID      int64     `json:"user_id"`
	DeliveredAt time.Time `json:"delivered_at"`
	Market      string    `json:"market"`
	Currency    string    `json:"currency"`
	// v8 direct fields — set by core-svc when publishing the event.
	// Fall back to computing from items[] if absent (backward compat with pre-v8 events).
	PriceMinor    int64 `json:"price_minor,omitempty"`
	CommissionBps int   `json:"commission_bps,omitempty"`
	// Items retains the per-line snapshot for the commission_snapshot audit column.
	Items []deliveredItemSnapshot `json:"items"`
	// Phase 4.4a additive fields — absent in pre-4.4a events (zero value is safe).
	ProductID       int64  `json:"product_id,omitempty"`
	ProductTitle    string `json:"product_title,omitempty"`
	ProductImageURL string `json:"product_image_url,omitempty"`
}

type deliveredItemSnapshot struct {
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

// StartConsumer blocks, reading ecom.order.delivered.v1 from Redis Streams
// and calling svc.CreatePlanFromDelivery for each message.
// Returns nil when ctx is cancelled.
func StartConsumer(ctx context.Context, bus eventbus.Consumer, svc Service) error {
	slog.Info("cashback: consumer starting",
		"topic", TopicOrderDelivered,
		"group", ConsumerGroup,
	)
	return bus.Subscribe(ctx, ConsumerGroup, TopicOrderDelivered, func(ctx context.Context, ev eventbus.Event) error {
		return handleDelivered(ctx, svc, ev)
	})
}

func handleDelivered(ctx context.Context, svc Service, ev eventbus.Event) error {
	var raw orderDeliveredPayload
	if err := json.Unmarshal(ev.Payload, &raw); err != nil {
		return fmt.Errorf("cashback: unmarshal delivered payload id=%s: %w", ev.EventID, err)
	}

	// Resolve PriceMinor and CommissionBps.
	// v8 events carry these directly; pre-v8 events carry them inside items[].
	priceMinor := raw.PriceMinor
	commissionBps := raw.CommissionBps
	if priceMinor == 0 && len(raw.Items) > 0 {
		// Compute from items for backward compat with pre-v8 core-svc events.
		for _, it := range raw.Items {
			priceMinor += it.UnitPriceMinor * int64(it.Qty)
		}
		// Use first item's commission bps (single-product-per-order assumption).
		commissionBps = raw.Items[0].CommissionPctBps
	}

	items := make([]CommissionSnapshotItem, len(raw.Items))
	for i, it := range raw.Items {
		items[i] = CommissionSnapshotItem{
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

	ode := OrderDeliveredEvent{
		OrderID:         raw.OrderID,
		UserID:          raw.UserID,
		DeliveredAt:     raw.DeliveredAt,
		Market:          ev.Market,
		Currency:        ev.Currency,
		PriceMinor:      priceMinor,
		CommissionBps:   commissionBps,
		Items:           items,
		ProductID:       raw.ProductID,
		ProductTitle:    raw.ProductTitle,
		ProductImageURL: raw.ProductImageURL,
	}

	plan, err := svc.CreatePlanFromDelivery(ctx, ode)
	if err != nil {
		slog.Error("cashback: CreatePlanFromDelivery failed",
			"order_id", ode.OrderID,
			"idempotency_key", ev.IdempotencyKey,
			"err", err,
		)
		return err
	}

	slog.Info("cashback: plan created or already exists",
		"order_id", ode.OrderID,
		"plan_id", plan.ID,
		"idempotency_key", ev.IdempotencyKey,
	)
	return nil
}
