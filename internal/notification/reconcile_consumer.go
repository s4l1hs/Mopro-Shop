package notification

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"

	"github.com/mopro/platform/internal/eventbus"
	pkg_slack "github.com/mopro/platform/pkg/slack"
)

const (
	// TopicReconcileDrift is the Redis Streams topic produced by internal/reconcile.
	TopicReconcileDrift = "fin.reconciliation.drift_critical.v1"
	// ConsumerGroupReconcile is the durable consumer group name.
	// Renaming requires a group migration procedure (ADR-0003).
	ConsumerGroupReconcile = "notification-reconcile-drift"
)

// driftPayload matches the JSON written by reconcile.Repository.InsertAlertInTx.
type driftPayload struct {
	AlertID           int64  `json:"alert_id"`
	CheckName         string `json:"check_name"`
	CurrencyOrPeriod  string `json:"currency_or_period"`
	DriftMinor        int64  `json:"drift_minor"`
}

// StartReconcileDriftConsumer blocks, reading fin.reconciliation.drift_critical.v1
// from Redis Streams and posting Slack alerts for each new message.
// Returns nil when ctx is cancelled.
func StartReconcileDriftConsumer(
	ctx context.Context,
	bus eventbus.Consumer,
	slack *pkg_slack.Client,
	dedup DedupStore,
	log *slog.Logger,
) error {
	if log == nil {
		log = slog.Default()
	}
	log.InfoContext(ctx, "notification: reconcile-drift consumer starting",
		"topic", TopicReconcileDrift,
		"group", ConsumerGroupReconcile,
	)
	return bus.Subscribe(ctx, ConsumerGroupReconcile, TopicReconcileDrift,
		func(ctx context.Context, ev eventbus.Event) error {
			return handleReconcileDrift(ctx, ev, slack, dedup, log)
		},
	)
}

func handleReconcileDrift(
	ctx context.Context,
	ev eventbus.Event,
	slack *pkg_slack.Client,
	dedup DedupStore,
	log *slog.Logger,
) error {
	var p driftPayload
	if err := json.Unmarshal(ev.Payload, &p); err != nil {
		// Malformed payload — do not retry (XACK will be issued by the caller on nil return).
		// Log as error but return nil so the message is ACKed and removed from PEL.
		log.ErrorContext(ctx, "notification: reconcile-drift: unmarshal payload",
			"event_id", ev.EventID, "err", err)
		return nil
	}

	alreadySent, err := dedup.MarkSent(ctx, ev.IdempotencyKey, TopicReconcileDrift)
	if err != nil {
		return fmt.Errorf("notification: reconcile-drift: dedup: %w", err)
	}
	if alreadySent {
		log.InfoContext(ctx, "notification: reconcile-drift: already sent, skipping",
			"idempotency_key", ev.IdempotencyKey)
		return nil
	}

	msg := pkg_slack.Message{
		Text: fmt.Sprintf(
			":red_circle: *CRITICAL: Ledger reconciliation drift detected*\n"+
				"• Check: `%s`\n"+
				"• Currency/Period: `%s`\n"+
				"• Drift (minor units): `%d`\n"+
				"• Alert ID: `%d`\n"+
				"Wallet is now in read-only mode. Investigate immediately.",
			p.CheckName, p.CurrencyOrPeriod, p.DriftMinor, p.AlertID,
		),
	}
	if err := slack.Post(ctx, msg); err != nil {
		// Return the error so the message stays in PEL and is redelivered.
		return fmt.Errorf("notification: reconcile-drift: slack post: %w", err)
	}

	log.InfoContext(ctx, "notification: reconcile-drift: slack alert sent",
		"alert_id", p.AlertID, "check", p.CheckName)
	return nil
}
