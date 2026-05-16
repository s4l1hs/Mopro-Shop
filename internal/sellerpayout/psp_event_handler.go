package sellerpayout

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/mopro/platform/internal/eventbus"
)

const (
	TopicSellerPspOnboarded  = "ecom.seller.psp_onboarded.v1"
	ConsumerGroupPspOnboarded = "sellerpayout-psp-reg"
)

// pspOnboardedPayload matches the JSON written by the seller module in core-svc.
type pspOnboardedPayload struct {
	SellerID    int64  `json:"seller_id"`
	PspMemberID string `json:"psp_member_id"`
	Market      string `json:"market"`
}

// StartPspOnboardedConsumer blocks, reading ecom.seller.psp_onboarded.v1 from Redis Streams
// and calling svc.HandlePspOnboarded for each message.
// Returns nil when ctx is cancelled.
func StartPspOnboardedConsumer(ctx context.Context, bus eventbus.Consumer, svc Service) error {
	slog.Info("sellerpayout: psp_onboarded consumer starting",
		"topic", TopicSellerPspOnboarded,
		"group", ConsumerGroupPspOnboarded,
	)
	return bus.Subscribe(ctx, ConsumerGroupPspOnboarded, TopicSellerPspOnboarded, func(ctx context.Context, ev eventbus.Event) error {
		return handlePspOnboarded(ctx, svc, ev)
	})
}

func handlePspOnboarded(ctx context.Context, svc Service, ev eventbus.Event) error {
	var raw pspOnboardedPayload
	if err := json.Unmarshal(ev.Payload, &raw); err != nil {
		return fmt.Errorf("sellerpayout: unmarshal psp_onboarded id=%s: %w", ev.EventID, err)
	}

	oe := PspOnboardedEvent{
		SellerID:    raw.SellerID,
		PspMemberID: raw.PspMemberID,
		Market:      raw.Market,
	}

	if err := svc.HandlePspOnboarded(ctx, oe); err != nil {
		slog.ErrorContext(ctx, "sellerpayout: HandlePspOnboarded failed",
			"seller_id", oe.SellerID,
			"err", err,
		)
		return err
	}

	slog.InfoContext(ctx, "sellerpayout: psp account registered",
		"seller_id", oe.SellerID,
		"psp_member_id", oe.PspMemberID,
	)
	return nil
}
