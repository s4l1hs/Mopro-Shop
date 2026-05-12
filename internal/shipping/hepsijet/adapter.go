// Package hepsijet implements shipping.Adapter for HepsiJet.
// Authentication: OAuth2 client_credentials via /oauth/token (Bearer, cached).
// Webhook auth: Authorization: Bearer <static webhook token> from config.
package hepsijet

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/mopro/platform/internal/shipping"
)

// Adapter implements shipping.Adapter for HepsiJet.
type Adapter struct {
	cfg    shipping.HepsiJetConfig
	client *client
}

// New constructs a HepsiJet Adapter from config.
func New(cfg shipping.HepsiJetConfig) *Adapter {
	return &Adapter{cfg: cfg, client: newClient(cfg.BaseURL, cfg.ClientID, cfg.ClientSecret)}
}

var stateMap = map[string]shipping.ShipmentState{
	"PACKAGE_RECEIVED":    shipping.ShipmentStatePickedUp,
	"IN_TRANSIT":          shipping.ShipmentStateInTransit,
	"OUT_FOR_DELIVERY":    shipping.ShipmentStateOutForDelivery,
	"DELIVERED":           shipping.ShipmentStateDelivered,
	"RETURNED_TO_SENDER":  shipping.ShipmentStateReturned,
	"CANCELLED":           shipping.ShipmentStateCancelled,
}

func mapState(raw string) shipping.ShipmentState {
	if s, ok := stateMap[raw]; ok {
		return s
	}
	return shipping.ShipmentStateInTransit
}

// ── CalculateRate ─────────────────────────────────────────────────────────────

type rateReq struct {
	WeightGrams int    `json:"weightGrams"`
	ServiceCode string `json:"serviceCode"`
}

type rateResp struct {
	TotalMinor int64  `json:"totalMinor"`
	Currency   string `json:"currency"`
	EstDays    int    `json:"estimatedDays"`
}

func (a *Adapter) CalculateRate(ctx context.Context, req shipping.ShipmentInput) (shipping.RateResult, error) {
	var out rateResp
	if err := a.client.do(ctx, http.MethodPost, "/api/v1/rate",
		rateReq{WeightGrams: req.WeightGrams, ServiceCode: req.ServiceLevel}, &out); err != nil {
		return shipping.RateResult{}, fmt.Errorf("hepsijet: CalculateRate: %w", err)
	}
	return shipping.RateResult{CostMinor: out.TotalMinor, Currency: out.Currency, EstimatedDays: out.EstDays, ServiceLevel: req.ServiceLevel}, nil
}

// ── CreateLabel ───────────────────────────────────────────────────────────────

type labelReq struct {
	OrderID        int64  `json:"orderId"`
	IdempotencyKey string `json:"idempotencyKey"`
	WeightGrams    int    `json:"weightGrams"`
}

type labelResp struct {
	TrackingNumber    string `json:"trackingNumber"`
	CarrierShipmentID string `json:"shipmentId"`
	LabelPDF          string `json:"labelPdfBase64"`
	CostMinor         int64  `json:"costMinor"`
	Currency          string `json:"currency"`
}

func (a *Adapter) CreateLabel(ctx context.Context, req shipping.ShipmentInput) (shipping.ShipmentResult, error) {
	var out labelResp
	if err := a.client.do(ctx, http.MethodPost, "/api/v1/shipment",
		labelReq{OrderID: req.OrderID, IdempotencyKey: req.IdempotencyKey, WeightGrams: req.WeightGrams}, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("hepsijet: CreateLabel: %w", err)
	}
	return shipping.ShipmentResult{
		TrackingNumber:    out.TrackingNumber,
		CarrierShipmentID: out.CarrierShipmentID,
		LabelPDFBase64:    out.LabelPDF,
		CostMinor:         out.CostMinor,
		CostCurrency:      out.Currency,
	}, nil
}

// ── TrackShipment ─────────────────────────────────────────────────────────────

type trackResp struct {
	Status      string `json:"status"`
	Description string `json:"description"`
	EventAt     string `json:"eventAt"`
}

func (a *Adapter) TrackShipment(ctx context.Context, trackingNumber string) (shipping.TrackResult, error) {
	var out trackResp
	if err := a.client.do(ctx, http.MethodGet, "/api/v1/shipment/"+trackingNumber, nil, &out); err != nil {
		return shipping.TrackResult{}, fmt.Errorf("hepsijet: TrackShipment: %w", err)
	}
	eventAt, _ := time.Parse(time.RFC3339, out.EventAt)
	return shipping.TrackResult{TrackingNumber: trackingNumber, State: mapState(out.Status), Description: out.Description, EventAt: eventAt}, nil
}

// ── CreateReturnLabel ─────────────────────────────────────────────────────────

func (a *Adapter) CreateReturnLabel(ctx context.Context, shipmentID int64) (shipping.ShipmentResult, error) {
	var out labelResp
	if err := a.client.do(ctx, http.MethodPost, fmt.Sprintf("/api/v1/shipment/%d/return", shipmentID), nil, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("hepsijet: CreateReturnLabel: %w", err)
	}
	return shipping.ShipmentResult{TrackingNumber: out.TrackingNumber, CarrierShipmentID: out.CarrierShipmentID, LabelPDFBase64: out.LabelPDF}, nil
}

// ── CancelShipment ────────────────────────────────────────────────────────────

func (a *Adapter) CancelShipment(ctx context.Context, trackingNumber string) error {
	return a.client.do(ctx, http.MethodDelete, "/api/v1/shipment/"+trackingNumber, nil, nil)
}

// ── HandleWebhook ─────────────────────────────────────────────────────────────

type webhookPayload struct {
	TrackingNumber string `json:"trackingNumber"`
	Status         string `json:"status"`
	Description    string `json:"description"`
	EventAt        string `json:"eventAt"`
}

// HandleWebhook validates Authorization: Bearer <webhookToken> and parses the event.
func (a *Adapter) HandleWebhook(_ context.Context, rawBody []byte, headers map[string]string) (shipping.WebhookEvent, error) {
	authHeader := headers["Authorization"]
	expected := "Bearer " + a.cfg.WebhookToken
	if !strings.EqualFold(authHeader, expected) {
		return shipping.WebhookEvent{}, shipping.ErrInvalidSignature
	}
	var p webhookPayload
	if err := json.Unmarshal(rawBody, &p); err != nil {
		return shipping.WebhookEvent{}, fmt.Errorf("hepsijet: webhook decode: %w", err)
	}
	eventAt, _ := time.Parse(time.RFC3339, p.EventAt)
	return shipping.WebhookEvent{
		TrackingNumber: p.TrackingNumber,
		State:          mapState(p.Status),
		Description:    p.Description,
		EventAt:        eventAt,
		CarrierRaw:     rawBody,
	}, nil
}
