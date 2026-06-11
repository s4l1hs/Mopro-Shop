package refund

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/mopro/platform/internal/eventbus"
)

const (
	// TopicReturnRefunded is produced by core-svc order.SellerApprove on settlement.
	TopicReturnRefunded = "ecom.return.refunded.v1"
	// ConsumerGroup is the refund engine's durable consumer group (registry).
	ConsumerGroup = "fin-refund-consumer"
)

// returnRefundedPayload matches order.returnRefundedPayload (the producer side).
type returnRefundedPayload struct {
	ReturnID          int64  `json:"return_id"`
	OrderID           int64  `json:"order_id"`
	UserID            int64  `json:"user_id"`
	RefundAmountMinor int64  `json:"refund_amount_minor"`
	Currency          string `json:"currency"`
	Market            string `json:"market"`
}

// StartConsumer blocks, reading ecom.return.refunded.v1 and settling each refund
// into the buyer's coin wallet. Returns nil when ctx is cancelled. A handler error
// leaves the message in the PEL for redelivery (SettleRefund is idempotent).
func StartConsumer(ctx context.Context, bus eventbus.Consumer, svc Service) error {
	slog.Info("refund: consumer starting", "topic", TopicReturnRefunded, "group", ConsumerGroup)
	return bus.Subscribe(ctx, ConsumerGroup, TopicReturnRefunded, func(ctx context.Context, ev eventbus.Event) error {
		return handleRefunded(ctx, svc, ev)
	})
}

func handleRefunded(ctx context.Context, svc Service, ev eventbus.Event) error {
	var raw returnRefundedPayload
	if err := json.Unmarshal(ev.Payload, &raw); err != nil {
		return fmt.Errorf("refund: unmarshal payload id=%s: %w", ev.EventID, err)
	}
	market := raw.Market
	if market == "" {
		market = ev.Market
	}
	return svc.SettleRefund(ctx, RefundEvent{
		ReturnID:          raw.ReturnID,
		OrderID:           raw.OrderID,
		UserID:            raw.UserID,
		RefundAmountMinor: raw.RefundAmountMinor,
		Market:            market,
	})
}
