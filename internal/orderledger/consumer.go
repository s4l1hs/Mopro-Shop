package orderledger

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/mopro/platform/internal/eventbus"
)

const (
	// TopicOrderPaid is the Redis Streams topic produced by core-svc order.MarkPaid.
	TopicOrderPaid = "ecom.order.paid.v1"
	// ConsumerGroup is the orderledger consumer group name.
	ConsumerGroup = "order-ledger-poster"
)

// orderPaidPayload matches the enriched JSON written by order.MarkPaid.
type orderPaidPayload struct {
	OrderID       int64              `json:"order_id"`
	UserID        int64              `json:"user_id"`
	SellerID      int64              `json:"seller_id"`
	PaidAt        time.Time          `json:"paid_at"`
	AmountMinor   int64              `json:"amount_minor"`
	ShippingMinor int64              `json:"shipping_minor"`
	Currency      string             `json:"currency"`
	Market        string             `json:"market"`
	Items         []orderPaidItem    `json:"items"`
}

type orderPaidItem struct {
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

// StartConsumer blocks, reading ecom.order.paid.v1 from Redis Streams
// and calling svc.PostCapture for each message. Returns nil on ctx cancel.
func StartConsumer(ctx context.Context, bus eventbus.Consumer, svc Service) error {
	slog.Info("orderledger: consumer starting",
		"topic", TopicOrderPaid,
		"group", ConsumerGroup,
	)
	return bus.Subscribe(ctx, ConsumerGroup, TopicOrderPaid, func(ctx context.Context, ev eventbus.Event) error {
		return handlePaid(ctx, svc, ev)
	})
}

func handlePaid(ctx context.Context, svc Service, ev eventbus.Event) error {
	var raw orderPaidPayload
	if err := json.Unmarshal(ev.Payload, &raw); err != nil {
		return fmt.Errorf("orderledger: unmarshal paid payload id=%s: %w", ev.EventID, err)
	}

	items := make([]PaidItem, len(raw.Items))
	for i, it := range raw.Items {
		items[i] = PaidItem{
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

	ope := OrderPaidEvent{
		OrderID:       raw.OrderID,
		UserID:        raw.UserID,
		SellerID:      raw.SellerID,
		PaidAt:        raw.PaidAt,
		GrossMinor:    raw.AmountMinor,
		ShippingMinor: raw.ShippingMinor,
		Currency:      ev.Currency,
		Market:        ev.Market,
		Items:         items,
	}

	if err := svc.PostCapture(ctx, ope); err != nil {
		slog.ErrorContext(ctx, "orderledger: PostCapture failed",
			"order_id", ope.OrderID,
			"idempotency_key", ev.IdempotencyKey,
			"err", err,
		)
		return err
	}

	slog.InfoContext(ctx, "orderledger: capture posted",
		"order_id", ope.OrderID,
		"idempotency_key", ev.IdempotencyKey,
	)
	return nil
}
