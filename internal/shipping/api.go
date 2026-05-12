package shipping

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Service is the carrier-agnostic shipping interface consumed by core-svc handlers
// and the poll worker. All methods are safe to call concurrently.
// Active carriers are selected at startup via Config; KARGO_DEFAULT sets the default.
// ARCHITECTURE.md § 8.4.
type Service interface {
	// ── Label / carrier operations ──────────────────────────────────────────

	// CalculateRate returns the shipping cost estimate for the given package.
	CalculateRate(ctx context.Context, carrier string, req ShipmentInput) (RateResult, error)

	// CreateLabel creates a shipment at the carrier and returns tracking info + label PDF.
	CreateLabel(ctx context.Context, carrier string, req ShipmentInput) (ShipmentResult, error)

	// TrackShipment polls the carrier for the current lifecycle state.
	TrackShipment(ctx context.Context, carrier, trackingNumber string) (TrackResult, error)

	// CreateReturnLabel creates a return shipment for an existing shipment.
	CreateReturnLabel(ctx context.Context, carrier string, shipmentID int64) (ShipmentResult, error)

	// CancelShipment requests cancellation at the carrier (before pickup only).
	CancelShipment(ctx context.Context, carrier, trackingNumber string) error

	// ── Webhook pipeline ─────────────────────────────────────────────────────

	// HandleWebhook validates the carrier-specific signature on rawBody and
	// returns a normalised WebhookEvent. Returns ErrInvalidSignature on failure.
	// Does NOT write to DB; call ProcessWebhookEvent to persist.
	HandleWebhook(ctx context.Context, carrier string, rawBody []byte, headers map[string]string) (WebhookEvent, error)

	// ProcessWebhookEvent persists the state change for a webhook event and,
	// if state == delivered, calls order.MarkDelivered.
	// If the tracking number is not found, logs and returns nil (prevents carrier retry).
	ProcessWebhookEvent(ctx context.Context, carrier string, event WebhookEvent) error

	// ── Poll pipeline ─────────────────────────────────────────────────────────

	// PollCarrier fetches stale pollable shipments for carrier, calls TrackShipment
	// on each, and persists any state changes (calling ProcessPollResult).
	// Designed to be called on a ticker by the shipping-poll-worker goroutine.
	PollCarrier(ctx context.Context, carrier string, limit int) error

	// ProcessPollResult persists a poll-detected state change for a specific shipment
	// and calls order.MarkDelivered if state == delivered.
	ProcessPollResult(ctx context.Context, shipmentID, orderID int64, result TrackResult) error
}

// Adapter is the per-carrier internal interface. shippingService dispatches to one
// of these based on the carrier name. Each carrier package registers an Adapter
// by supplying a factory to NewService via the adapters map parameter.
type Adapter interface {
	CalculateRate(ctx context.Context, req ShipmentInput) (RateResult, error)
	CreateLabel(ctx context.Context, req ShipmentInput) (ShipmentResult, error)
	TrackShipment(ctx context.Context, trackingNumber string) (TrackResult, error)
	CreateReturnLabel(ctx context.Context, shipmentID int64) (ShipmentResult, error)
	HandleWebhook(ctx context.Context, rawBody []byte, headers map[string]string) (WebhookEvent, error)
	CancelShipment(ctx context.Context, trackingNumber string) error
}

// Repository manages shipping_schema in postgres-ecom.
// All write methods called within a transaction participate in the caller's ACID guarantee.
type Repository interface {
	InsertShipment(ctx context.Context, tx pgx.Tx, s Shipment) (Shipment, error)
	FindShipmentByOrderID(ctx context.Context, orderID int64) (Shipment, error)
	FindShipmentByTrackingNumber(ctx context.Context, carrier, trackingNumber string) (Shipment, error)
	UpdateShipmentState(ctx context.Context, tx pgx.Tx, id int64, state ShipmentState, deliveredAt *time.Time) error
	InsertShipmentEvent(ctx context.Context, tx pgx.Tx, e ShipmentEvent) error
	// FindPollableShipments returns shipments in active states for carrier where
	// last_polled_at IS NULL or < now()-~5min. limit caps the batch size.
	FindPollableShipments(ctx context.Context, carrier string, limit int) ([]Shipment, error)
	UpdateLastPolledAt(ctx context.Context, id int64) error
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
}
