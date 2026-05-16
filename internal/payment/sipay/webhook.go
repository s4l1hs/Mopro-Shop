package sipay

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/payment"
)

const (
	webhookRedisKeyPrefix = "webhook:sipay:"
	webhookRedisExpiry    = 7 * 24 * time.Hour
	webhookMaxBodyBytes   = 64 * 1024 // 64 KB
)

// webhookConfirmer is the subset of *Adapter needed by WebhookHandler.
// Extracted to an interface so tests can inject stubs returning arbitrary event types.
type webhookConfirmer interface {
	ConfirmWebhook(ctx context.Context, rawBody []byte, sig string) (payment.PaymentEvent, error)
}

// WebhookHandler handles Sipay webhook POST calls with 3-layer deduplication:
//
//  1. Sipay HMAC-SHA512 signature verification.
//  2. DB transaction: InsertPaymentIntent + outbox.Insert — both protected by
//     UNIQUE(idempotency_key) constraints (source of truth).
//  3. Redis fast-path: after a successful DB commit, a Redis key is written with
//     a 7-day TTL. Future duplicates skip the DB entirely via a GET before the TX.
//
// The Redis key is written AFTER the DB commit (not before) to avoid cache poisoning
// on a failed transaction.
type WebhookHandler struct {
	adapter    webhookConfirmer
	repo       payment.Repository
	outboxRepo outbox.Repository
	rdb        *redis.Client
	market     string
	currency   string
	log        *slog.Logger
}

// NewWebhookHandler constructs a WebhookHandler.
func NewWebhookHandler(
	adapter *Adapter,
	repo payment.Repository,
	outboxRepo outbox.Repository,
	rdb *redis.Client,
	market, currency string,
	log *slog.Logger,
) *WebhookHandler {
	if log == nil {
		log = slog.Default()
	}
	return &WebhookHandler{
		adapter:    adapter,
		repo:       repo,
		outboxRepo: outboxRepo,
		rdb:        rdb,
		market:     market,
		currency:   currency,
		log:        log,
	}
}

// NewWebhookHandlerWithConfirmer is identical to NewWebhookHandler but accepts
// any webhookConfirmer, enabling unit tests to inject stubs.
func NewWebhookHandlerWithConfirmer(
	confirmer webhookConfirmer,
	repo payment.Repository,
	outboxRepo outbox.Repository,
	rdb *redis.Client,
	market, currency string,
	log *slog.Logger,
) *WebhookHandler {
	if log == nil {
		log = slog.Default()
	}
	return &WebhookHandler{
		adapter:    confirmer,
		repo:       repo,
		outboxRepo: outboxRepo,
		rdb:        rdb,
		market:     market,
		currency:   currency,
		log:        log,
	}
}

// ServeHTTP implements http.Handler.
func (h *WebhookHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	body, err := io.ReadAll(io.LimitReader(r.Body, webhookMaxBodyBytes))
	if err != nil {
		h.log.Error("sipay webhook: read body", "err", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// Extract hash_key from body to pass as sig to ConfirmWebhook.
	var raw struct {
		HashKey string `json:"hash_key"`
	}
	if err := json.Unmarshal(body, &raw); err != nil {
		h.log.Warn("sipay webhook: invalid JSON")
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// Layer 1: Signature verification + event normalisation.
	ev, err := h.adapter.ConfirmWebhook(ctx, body, raw.HashKey)
	if err != nil {
		if errors.Is(err, payment.ErrInvalidSignature) {
			h.log.Warn("sipay webhook: invalid signature", "invoice_id", raw.HashKey)
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		h.log.Error("sipay webhook: ConfirmWebhook", "err", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// Reject unknown event types before any DB or outbox work.
	if _, known := knownPaymentEventTypes[ev.Type]; !known {
		h.log.Warn("sipay webhook: unknown event type", "type", ev.Type, "provider_ref", ev.ProviderRef)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// Layer 2 fast-path: check Redis before hitting the DB.
	redisKey := webhookRedisKeyPrefix + ev.ProviderRef
	exists, err := h.rdb.Exists(ctx, redisKey).Result()
	if err == nil && exists > 0 {
		// Already processed; return 200 to prevent Sipay from retrying.
		w.WriteHeader(http.StatusOK)
		return
	}

	// Layer 2 (DB) + Layer 3 (outbox UNIQUE):
	var alreadyDone bool
	txErr := h.repo.WithTx(ctx, func(tx pgx.Tx) error {
		rawJSON, _ := json.Marshal(json.RawMessage(body))
		intent := payment.PaymentIntent{
			OrderID:         ev.OrderID,
			IdempotencyKey:  ev.ProviderRef,
			Provider:        "sipay",
			ProviderRef:     ev.ProviderRef,
			ProviderOrderNo: ev.ProviderOrderNo,
			Status:          paymentStatusFromEvent(ev.Type),
			AmountMinor:     ev.AmountMinor,
			Currency:        ev.Currency,
			RawResponse:     rawJSON,
		}
		if ev.Type == payment.PaymentEventCaptured {
			now := ev.OccurredAt
			intent.CapturedAt = &now
		}

		_, insertErr := h.repo.InsertPaymentIntent(ctx, tx, intent)
		if errors.Is(insertErr, payment.ErrPaymentAlreadyCaptured) {
			// DB UNIQUE constraint fired — already processed at DB level.
			alreadyDone = true
			return nil
		}
		if insertErr != nil {
			return fmt.Errorf("sipay webhook: insert payment intent: %w", insertErr)
		}

		payload, _ := json.Marshal(map[string]any{
			"provider_ref":   ev.ProviderRef,
			"order_id":       ev.OrderID,
			"amount_minor":   ev.AmountMinor,
			"currency":       ev.Currency,
			"event_type":     string(ev.Type),
			"occurred_at":    ev.OccurredAt.Format(time.RFC3339),
			"failure_reason": ev.FailureReason,
			"refund_ref":     ev.RefundRef,
		})
		return h.outboxRepo.Insert(ctx, tx, outbox.Row{
			Aggregate:      "payment",
			EventType:      outboxEventType(ev.Type),
			Payload:        payload,
			IdempotencyKey: "psp:" + ev.ProviderRef,
			Market:         h.market,
			Currency:       h.currency,
		})
	})

	if txErr != nil {
		h.log.Error("sipay webhook: transaction failed", "err", txErr, "provider_ref", ev.ProviderRef)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	if alreadyDone {
		// Already in DB — still write Redis to short-circuit future duplicates.
		_ = h.rdb.Set(ctx, redisKey, "1", webhookRedisExpiry).Err()
		w.WriteHeader(http.StatusOK)
		return
	}

	// Layer 3 post-commit: write Redis key so future duplicates bypass the DB.
	if err := h.rdb.Set(ctx, redisKey, "1", webhookRedisExpiry).Err(); err != nil {
		// Non-fatal: DB is the source of truth; Redis is best-effort fast path.
		h.log.Warn("sipay webhook: redis set failed (non-fatal)", "err", err, "key", redisKey)
	}

	h.log.Info("sipay webhook: processed",
		"type", ev.Type, "provider_ref", ev.ProviderRef, "amount_minor", ev.AmountMinor)
	w.WriteHeader(http.StatusOK)
}

func paymentStatusFromEvent(t payment.PaymentEventType) payment.PaymentStatus {
	switch t {
	case payment.PaymentEventCaptured:
		return payment.PaymentStatusCaptured
	case payment.PaymentEventFailed:
		return payment.PaymentStatusFailed
	case payment.PaymentEventRefunded:
		return payment.PaymentStatusRefunded
	default:
		return payment.PaymentStatusUnknown
	}
}

// knownPaymentEventTypes is the guard for the early-return check above.
// outboxEventType must stay in sync with this set.
var knownPaymentEventTypes = map[payment.PaymentEventType]struct{}{
	payment.PaymentEventCaptured: {},
	payment.PaymentEventFailed:   {},
	payment.PaymentEventRefunded: {},
}

func outboxEventType(t payment.PaymentEventType) string {
	switch t {
	case payment.PaymentEventCaptured:
		return "ecom.payment.captured.v1"
	case payment.PaymentEventFailed:
		return "ecom.payment.failed.v1"
	default: // PaymentEventRefunded
		return "ecom.payment.refunded.v1"
	}
}
