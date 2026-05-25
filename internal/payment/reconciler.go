package payment

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/outbox"
)

const (
	reconcilerInterval  = 60 * time.Second
	reconcilerBatchSize = 50
)

// Reconciler polls for payment intents that are stuck in 'pending' state past
// their expiry and reconciles them via CheckStatus. It catches webhooks that
// Sipay failed to deliver.
//
// Wire as a goroutine in cmd/core-svc/main.go:
//
//	go func() { _ = reconciler.Run(ctx) }()
type Reconciler struct {
	repo       Repository
	svc        Service
	outboxRepo outbox.Repository
	market     string
	currency   string
	log        *slog.Logger
	interval   time.Duration
}

// NewReconciler creates a Reconciler. interval defaults to 60s if zero.
func NewReconciler(
	repo Repository,
	svc Service,
	outboxRepo outbox.Repository,
	market, currency string,
	log *slog.Logger,
) *Reconciler {
	if log == nil {
		log = slog.Default()
	}
	return &Reconciler{
		repo:       repo,
		svc:        svc,
		outboxRepo: outboxRepo,
		market:     market,
		currency:   currency,
		log:        log,
		interval:   reconcilerInterval,
	}
}

// Run executes reconciliation passes on the configured interval until ctx is cancelled.
func (r *Reconciler) Run(ctx context.Context) error {
	ticker := time.NewTicker(r.interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if err := r.runOnce(ctx); err != nil {
				r.log.Error("payment reconciler: pass failed", "err", err)
				// Non-fatal: log and continue; next tick will retry.
			}
		}
	}
}

// runOnce performs a single reconciliation pass.
func (r *Reconciler) runOnce(ctx context.Context) error {
	pending, err := r.repo.FindExpiredPendingPayments(ctx, reconcilerBatchSize)
	if err != nil {
		return fmt.Errorf("payment reconciler: find expired: %w", err)
	}
	if len(pending) == 0 {
		return nil
	}
	r.log.Info("payment reconciler: checking expired payments", "count", len(pending))

	for _, p := range pending {
		if err := r.reconcileOne(ctx, p); err != nil {
			r.log.Warn("payment reconciler: reconcileOne failed",
				"provider_ref", p.ProviderRef, "err", err)
			// Continue to next row; don't abort the whole pass.
		}
	}
	return nil
}

func (r *Reconciler) reconcileOne(ctx context.Context, p PaymentIntent) error {
	providerStatus, err := r.svc.CheckStatus(ctx, p.ProviderRef)
	if err != nil {
		return fmt.Errorf("CheckStatus(%s): %w", p.ProviderRef, err)
	}

	// If still pending or unknown, leave it for the next pass.
	if providerStatus == PaymentStatusPending || providerStatus == PaymentStatusUnknown {
		r.log.Debug("payment reconciler: payment still pending at PSP",
			"provider_ref", p.ProviderRef, "status", providerStatus)
		return nil
	}

	newStatus := providerStatus
	idempotencyKey := "reconcile:psp:" + p.ProviderRef

	return r.repo.WithTx(ctx, func(tx pgx.Tx) error {
		now := time.Now().UTC().Format(time.RFC3339Nano)
		var capturedAt, failedAt, refundedAt *string
		switch newStatus {
		case PaymentStatusCaptured:
			capturedAt = &now
		case PaymentStatusFailed:
			failedAt = &now
		case PaymentStatusRefunded:
			refundedAt = &now
		}

		if err := r.repo.UpdatePaymentStatus(ctx, tx, p.ProviderRef, newStatus,
			capturedAt, failedAt, refundedAt, "", "", 0); err != nil {
			return fmt.Errorf("UpdatePaymentStatus: %w", err)
		}

		payload, _ := json.Marshal(map[string]any{
			"provider_ref":   p.ProviderRef,
			"order_id":       p.OrderID,
			"amount_minor":   p.AmountMinor,
			"currency":       p.Currency,
			"event_type":     string(paymentEventTypeFromStatus(newStatus)),
			"occurred_at":    now,
			"failure_reason": "",
			"source":         "reconciler",
		})
		if err := r.outboxRepo.Insert(ctx, tx, outbox.Row{
			Aggregate:      "payment",
			EventType:      outboxEventFromStatus(newStatus),
			Payload:        payload,
			IdempotencyKey: idempotencyKey,
			Market:         r.market,
			Currency:       r.currency,
		}); err != nil {
			return fmt.Errorf("outbox insert: %w", err)
		}

		r.log.Info("payment reconciler: reconciled",
			"provider_ref", p.ProviderRef, "new_status", newStatus)
		return nil
	})
}

func paymentEventTypeFromStatus(s PaymentStatus) PaymentEventType {
	switch s {
	case PaymentStatusCaptured:
		return PaymentEventCaptured
	case PaymentStatusRefunded:
		return PaymentEventRefunded
	default:
		return PaymentEventFailed
	}
}

func outboxEventFromStatus(s PaymentStatus) string {
	switch s {
	case PaymentStatusCaptured:
		return "ecom.payment.captured.v1"
	case PaymentStatusRefunded:
		return "ecom.payment.refunded.v1"
	default:
		return "ecom.payment.failed.v1"
	}
}
