package sellerpayout

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/mopro/platform/internal/eventbus"
)

const (
	TopicSellerFraudHoldSet   = "ecom.seller.fraud_hold_set.v1"
	ConsumerGroupFraudHoldSet = "sellerpayout-fraud-hold"
)

// fraudHoldPayload matches the JSON written by the antifraud module in core-svc.
type fraudHoldPayload struct {
	SellerID int64  `json:"seller_id"`
	Market   string `json:"market"`
	Currency string `json:"currency"`
	Reason   string `json:"reason"`
}

// StartFraudHoldConsumer blocks, reading ecom.seller.fraud_hold_set.v1 from Redis Streams
// and calling svc.HandleFraudHoldSet for each message.
func StartFraudHoldConsumer(ctx context.Context, bus eventbus.Consumer, svc Service) error {
	slog.Info("sellerpayout: fraud_hold consumer starting",
		"topic", TopicSellerFraudHoldSet,
		"group", ConsumerGroupFraudHoldSet,
	)
	return bus.Subscribe(ctx, ConsumerGroupFraudHoldSet, TopicSellerFraudHoldSet, func(ctx context.Context, ev eventbus.Event) error {
		return handleFraudHoldSet(ctx, svc, ev)
	})
}

func handleFraudHoldSet(ctx context.Context, svc Service, ev eventbus.Event) error {
	var raw fraudHoldPayload
	if err := json.Unmarshal(ev.Payload, &raw); err != nil {
		return fmt.Errorf("sellerpayout: unmarshal fraud_hold_set id=%s: %w", ev.EventID, err)
	}

	fhe := FraudHoldSetEvent{
		SellerID: raw.SellerID,
		Market:   raw.Market,
		Currency: raw.Currency,
		Reason:   raw.Reason,
	}

	if err := svc.HandleFraudHoldSet(ctx, fhe); err != nil {
		slog.ErrorContext(ctx, "sellerpayout: HandleFraudHoldSet failed",
			"seller_id", fhe.SellerID,
			"err", err,
		)
		return err
	}

	slog.WarnContext(ctx, "sellerpayout: fraud hold recorded",
		"seller_id", fhe.SellerID,
		"reason", fhe.Reason,
	)
	return nil
}

// handleFraudHoldSet inserts a ledger_alerts row for any in-flight payout batches
// for the affected seller. ReconcileProcessing will detect the open alert and skip Tx2.
func (s *payoutService) handleFraudHoldSet(ctx context.Context, ev FraudHoldSetEvent) error {
	msg := fmt.Sprintf("fraud hold set for seller %d: %s", ev.SellerID, ev.Reason)
	return s.repo.InsertLedgerAlert(ctx, LedgerAlert{
		Severity:  "SEV1",
		Currency:  ev.Currency,
		AlertType: "fraud_hold",
		Message:   msg,
	})
}
