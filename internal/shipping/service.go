package shipping

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/order"
)

type shippingService struct {
	adapters       map[string]Adapter
	repo           Repository
	orderSvc       order.Service
	defaultCarrier string
}

// NewService builds a shippingService from the populated adapters map.
// In production (GO_ENV=production) KARGO_DEFAULT must be set and its adapter
// must be present (D2 guard).
// Non-default carriers with absent env vars are silently skipped in dev
// (caller passes empty adapter for missing carriers).
func NewService(defaultCarrier string, adapters map[string]Adapter, repo Repository, orderSvc order.Service) (Service, error) {
	if os.Getenv("GO_ENV") == "production" {
		if defaultCarrier == "" {
			return nil, fmt.Errorf("shipping: KARGO_DEFAULT is required in production")
		}
		if _, ok := adapters[defaultCarrier]; !ok {
			return nil, fmt.Errorf("shipping: KARGO_DEFAULT=%q adapter not configured in production", defaultCarrier)
		}
	}
	return &shippingService{
		adapters:       adapters,
		repo:           repo,
		orderSvc:       orderSvc,
		defaultCarrier: defaultCarrier,
	}, nil
}

func (s *shippingService) adapter(carrier string) (Adapter, error) {
	a, ok := s.adapters[carrier]
	if !ok {
		return nil, fmt.Errorf("%w: %s", ErrInvalidCarrier, carrier)
	}
	return a, nil
}

// ── carrier operations ────────────────────────────────────────────────────────

func (s *shippingService) CalculateRate(ctx context.Context, carrier string, req ShipmentInput) (RateResult, error) {
	a, err := s.adapter(carrier)
	if err != nil {
		return RateResult{}, err
	}
	return a.CalculateRate(ctx, req)
}

func (s *shippingService) CreateLabel(ctx context.Context, carrier string, req ShipmentInput) (ShipmentResult, error) {
	a, err := s.adapter(carrier)
	if err != nil {
		return ShipmentResult{}, err
	}
	return a.CreateLabel(ctx, req)
}

func (s *shippingService) TrackShipment(ctx context.Context, carrier, trackingNumber string) (TrackResult, error) {
	a, err := s.adapter(carrier)
	if err != nil {
		return TrackResult{}, err
	}
	return a.TrackShipment(ctx, trackingNumber)
}

func (s *shippingService) CreateReturnLabel(ctx context.Context, carrier string, shipmentID int64) (ShipmentResult, error) {
	a, err := s.adapter(carrier)
	if err != nil {
		return ShipmentResult{}, err
	}
	return a.CreateReturnLabel(ctx, shipmentID)
}

func (s *shippingService) CancelShipment(ctx context.Context, carrier, trackingNumber string) error {
	a, err := s.adapter(carrier)
	if err != nil {
		return err
	}
	return a.CancelShipment(ctx, trackingNumber)
}

// ── webhook pipeline ──────────────────────────────────────────────────────────

func (s *shippingService) HandleWebhook(ctx context.Context, carrier string, rawBody []byte, headers map[string]string) (WebhookEvent, error) {
	a, err := s.adapter(carrier)
	if err != nil {
		return WebhookEvent{}, err
	}
	return a.HandleWebhook(ctx, rawBody, headers)
}

// ProcessWebhookEvent persists the state change for a webhook event and,
// if state == delivered, triggers order.MarkDelivered.
func (s *shippingService) ProcessWebhookEvent(ctx context.Context, carrier string, event WebhookEvent) error {
	shipment, err := s.repo.FindShipmentByTrackingNumber(ctx, carrier, event.TrackingNumber)
	if err != nil {
		if errors.Is(err, ErrShipmentNotFound) {
			slog.Warn("shipping: webhook for unknown tracking", "carrier", carrier, "tracking", event.TrackingNumber)
			return nil // return nil; prevents carrier retry for legitimate unknown parcels
		}
		return fmt.Errorf("shipping: ProcessWebhookEvent lookup: %w", err)
	}

	var deliveredAt *time.Time
	if event.State == ShipmentStateDelivered {
		t := event.EventAt
		deliveredAt = &t
	}

	if err := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		if err := s.repo.UpdateShipmentState(ctx, tx, shipment.ID, event.State, deliveredAt); err != nil {
			return err
		}
		return s.repo.InsertShipmentEvent(ctx, tx, ShipmentEvent{
			ShipmentID: shipment.ID,
			State:      event.State,
			Source:     "webhook",
			CarrierRaw: event.CarrierRaw,
			EventAt:    event.EventAt,
		})
	}); err != nil {
		return fmt.Errorf("shipping: ProcessWebhookEvent persist: %w", err)
	}

	if event.State == ShipmentStateDelivered {
		if err := s.orderSvc.MarkDelivered(ctx, shipment.OrderID, event.EventAt); err != nil {
			// Logged but not propagated: shipping side committed; MarkDelivered is
			// idempotent; carrier webhook retry will complete the chain if needed.
			slog.Error("shipping: ProcessWebhookEvent MarkDelivered", "order_id", shipment.OrderID, "err", err)
		}
	}
	return nil
}

// ── poll pipeline ─────────────────────────────────────────────────────────────

// PollCarrier fetches stale in-transit shipments for carrier, calls TrackShipment
// on each, and processes any state changes via ProcessPollResult.
// UpdateLastPolledAt is called BEFORE the carrier API call to prevent stampede.
func (s *shippingService) PollCarrier(ctx context.Context, carrier string, limit int) error {
	a, err := s.adapter(carrier)
	if err != nil {
		return err
	}

	shipments, err := s.repo.FindPollableShipments(ctx, carrier, limit)
	if err != nil {
		return fmt.Errorf("shipping: PollCarrier FindPollableShipments: %w", err)
	}

	for _, sh := range shipments {
		_ = s.repo.UpdateLastPolledAt(ctx, sh.ID) // before API call; prevents duplicate polling

		result, err := a.TrackShipment(ctx, sh.TrackingNumber)
		if err != nil {
			slog.Warn("shipping poll: TrackShipment", "carrier", carrier, "tracking", sh.TrackingNumber, "err", err)
			continue
		}

		if result.State == sh.State {
			continue // no state change; nothing to persist
		}

		if err := s.ProcessPollResult(ctx, sh.ID, sh.OrderID, result); err != nil {
			slog.Error("shipping poll: ProcessPollResult", "carrier", carrier, "shipment_id", sh.ID, "err", err)
		}
	}
	return nil
}

// ProcessPollResult persists a poll-detected state change and triggers
// order.MarkDelivered if state == delivered.
func (s *shippingService) ProcessPollResult(ctx context.Context, shipmentID, orderID int64, result TrackResult) error {
	var deliveredAt *time.Time
	if result.State == ShipmentStateDelivered {
		t := result.EventAt
		deliveredAt = &t
	}

	if err := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		if err := s.repo.UpdateShipmentState(ctx, tx, shipmentID, result.State, deliveredAt); err != nil {
			return err
		}
		return s.repo.InsertShipmentEvent(ctx, tx, ShipmentEvent{
			ShipmentID: shipmentID,
			State:      result.State,
			Source:     "poll",
			CarrierRaw: result.CarrierRaw,
			EventAt:    result.EventAt,
		})
	}); err != nil {
		return fmt.Errorf("shipping: ProcessPollResult persist: %w", err)
	}

	if result.State == ShipmentStateDelivered {
		if err := s.orderSvc.MarkDelivered(ctx, orderID, result.EventAt); err != nil {
			slog.Error("shipping poll: MarkDelivered", "order_id", orderID, "err", err)
		}
	}
	return nil
}
