package sellerpayout

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
	// ConsumerGroup is the seller payout engine's durable consumer group name.
	// Renaming requires a group migration procedure (ADR-0003).
	ConsumerGroup = "sellerpayout-engine"
)

// orderDeliveredPayload matches the JSON written by order.buildDeliveredPayload.
type orderDeliveredPayload struct {
	OrderID     int64               `json:"order_id"`
	DeliveredAt time.Time           `json:"delivered_at"`
	Market      string              `json:"market"`
	Currency    string              `json:"currency"`
	Items       []deliveredItemSnap `json:"items"`
}

type deliveredItemSnap struct {
	SellerID       int64 `json:"seller_id"`
	SellerNetMinor int64 `json:"seller_net_minor"`
}

// StartConsumer blocks, reading ecom.order.delivered.v1 from Redis Streams
// and calling svc.SchedulePayoutsForOrder for each message.
// Returns nil when ctx is cancelled.
func StartConsumer(ctx context.Context, bus eventbus.Consumer, svc Service) error {
	slog.Info("sellerpayout: consumer starting",
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
		return fmt.Errorf("sellerpayout: unmarshal delivered payload id=%s: %w", ev.EventID, err)
	}

	items := make([]DeliveredItem, len(raw.Items))
	for i, it := range raw.Items {
		items[i] = DeliveredItem{
			SellerID:       it.SellerID,
			SellerNetMinor: it.SellerNetMinor,
		}
	}

	ode := OrderDeliveredEvent{
		OrderID:     raw.OrderID,
		DeliveredAt: raw.DeliveredAt,
		Market:      ev.Market,
		Currency:    ev.Currency,
		Items:       items,
	}

	if err := svc.SchedulePayoutsForOrder(ctx, ode); err != nil {
		slog.Error("sellerpayout: SchedulePayoutsForOrder failed",
			"order_id", ode.OrderID,
			"idempotency_key", ev.IdempotencyKey,
			"err", err,
		)
		return err
	}

	slog.Info("sellerpayout: payouts scheduled",
		"order_id", ode.OrderID,
		"idempotency_key", ev.IdempotencyKey,
	)
	return nil
}
