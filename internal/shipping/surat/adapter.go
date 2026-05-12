// Package surat implements shipping.Adapter for Sürat Kargo.
// Authentication: Bearer JWT via /api/v1/auth/login (cached with 30s pre-expiry buffer).
// Webhook signature: X-Surat-Sign = hex(HMAC-SHA256(rawBody, webhookSecret)).
package surat

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/mopro/platform/internal/shipping"
)

// Adapter implements shipping.Adapter for Sürat Kargo.
type Adapter struct {
	cfg    shipping.SuratConfig
	client *client
}

// New constructs a Sürat Adapter from config.
func New(cfg shipping.SuratConfig) *Adapter {
	return &Adapter{cfg: cfg, client: newClient(cfg.BaseURL, cfg.Username, cfg.Password)}
}

// ── carrier state map ─────────────────────────────────────────────────────────

var stateMap = map[string]shipping.ShipmentState{
	"RECEIVED":          shipping.ShipmentStatePickedUp,
	"IN_TRANSIT":        shipping.ShipmentStateInTransit,
	"OUT_FOR_DELIVERY":  shipping.ShipmentStateOutForDelivery,
	"DELIVERED":         shipping.ShipmentStateDelivered,
	"RETURNED":          shipping.ShipmentStateReturned,
	"CANCELLED":         shipping.ShipmentStateCancelled,
}

func mapState(raw string) shipping.ShipmentState {
	if s, ok := stateMap[raw]; ok {
		return s
	}
	return shipping.ShipmentStateInTransit
}

// ── CalculateRate ─────────────────────────────────────────────────────────────

type rateRequest struct {
	WeightGrams int    `json:"weightGrams"`
	ServiceCode string `json:"serviceCode"`
}

type rateResponse struct {
	Data struct {
		TotalMinor int64  `json:"totalMinor"`
		Currency   string `json:"currency"`
		EstDays    int    `json:"estimatedDays"`
	} `json:"Data"`
}

func (a *Adapter) CalculateRate(ctx context.Context, req shipping.ShipmentInput) (shipping.RateResult, error) {
	in := rateRequest{WeightGrams: req.WeightGrams, ServiceCode: req.ServiceLevel}
	var out rateResponse
	if err := a.client.do(ctx, http.MethodPost, "/api/v1/shipment/rate", in, &out); err != nil {
		return shipping.RateResult{}, fmt.Errorf("surat: CalculateRate: %w", err)
	}
	return shipping.RateResult{
		CostMinor:     out.Data.TotalMinor,
		Currency:      out.Data.Currency,
		EstimatedDays: out.Data.EstDays,
		ServiceLevel:  req.ServiceLevel,
	}, nil
}

// ── CreateLabel ───────────────────────────────────────────────────────────────

type labelRequest struct {
	OrderID        int64  `json:"orderId"`
	IdempotencyKey string `json:"idempotencyKey"`
	WeightGrams    int    `json:"weightGrams"`
	ServiceCode    string `json:"serviceCode"`
}

type labelResponse struct {
	Data struct {
		TrackingNumber    string `json:"trackingNumber"`
		CarrierShipmentID string `json:"shipmentId"`
		LabelPDF          string `json:"labelPdfBase64"`
		CostMinor         int64  `json:"costMinor"`
		Currency          string `json:"currency"`
	} `json:"Data"`
}

func (a *Adapter) CreateLabel(ctx context.Context, req shipping.ShipmentInput) (shipping.ShipmentResult, error) {
	in := labelRequest{
		OrderID:        req.OrderID,
		IdempotencyKey: req.IdempotencyKey,
		WeightGrams:    req.WeightGrams,
		ServiceCode:    req.ServiceLevel,
	}
	var out labelResponse
	if err := a.client.do(ctx, http.MethodPost, "/api/v1/shipment/create", in, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("surat: CreateLabel: %w", err)
	}
	return shipping.ShipmentResult{
		TrackingNumber:    out.Data.TrackingNumber,
		CarrierShipmentID: out.Data.CarrierShipmentID,
		LabelPDFBase64:    out.Data.LabelPDF,
		CostMinor:         out.Data.CostMinor,
		CostCurrency:      out.Data.Currency,
	}, nil
}

// ── TrackShipment ─────────────────────────────────────────────────────────────

type trackResponse struct {
	Data struct {
		Status      string `json:"status"`
		Description string `json:"description"`
		EventAt     string `json:"eventAt"` // RFC3339
	} `json:"Data"`
}

func (a *Adapter) TrackShipment(ctx context.Context, trackingNumber string) (shipping.TrackResult, error) {
	var out trackResponse
	if err := a.client.do(ctx, http.MethodGet, "/api/v1/shipment/track/"+trackingNumber, nil, &out); err != nil {
		return shipping.TrackResult{}, fmt.Errorf("surat: TrackShipment: %w", err)
	}
	eventAt, _ := time.Parse(time.RFC3339, out.Data.EventAt)
	return shipping.TrackResult{
		TrackingNumber: trackingNumber,
		State:          mapState(out.Data.Status),
		Description:    out.Data.Description,
		EventAt:        eventAt,
	}, nil
}

// ── CreateReturnLabel ─────────────────────────────────────────────────────────

func (a *Adapter) CreateReturnLabel(ctx context.Context, shipmentID int64) (shipping.ShipmentResult, error) {
	var out labelResponse
	if err := a.client.do(ctx, http.MethodPost,
		fmt.Sprintf("/api/v1/shipment/%d/return", shipmentID), nil, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("surat: CreateReturnLabel: %w", err)
	}
	return shipping.ShipmentResult{
		TrackingNumber:    out.Data.TrackingNumber,
		CarrierShipmentID: out.Data.CarrierShipmentID,
		LabelPDFBase64:    out.Data.LabelPDF,
	}, nil
}

// ── CancelShipment ────────────────────────────────────────────────────────────

func (a *Adapter) CancelShipment(ctx context.Context, trackingNumber string) error {
	if err := a.client.do(ctx, http.MethodPost,
		"/api/v1/shipment/cancel/"+trackingNumber, nil, nil); err != nil {
		return fmt.Errorf("surat: CancelShipment: %w", err)
	}
	return nil
}

// ── HandleWebhook ─────────────────────────────────────────────────────────────

type webhookPayload struct {
	TrackingNumber string `json:"trackingNumber"`
	Status         string `json:"status"`
	Description    string `json:"description"`
	EventAt        string `json:"eventAt"`
}

// HandleWebhook validates X-Surat-Sign: hex(HMAC-SHA256(body, secret)) and parses.
func (a *Adapter) HandleWebhook(ctx context.Context, rawBody []byte, headers map[string]string) (shipping.WebhookEvent, error) {
	sig := headers["X-Surat-Sign"]
	if !validHMAC(rawBody, a.cfg.WebhookSecret, sig) {
		return shipping.WebhookEvent{}, shipping.ErrInvalidSignature
	}
	var p webhookPayload
	if err := json.Unmarshal(rawBody, &p); err != nil {
		return shipping.WebhookEvent{}, fmt.Errorf("surat: webhook decode: %w", err)
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

func validHMAC(body []byte, secret, sig string) bool {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(sig))
}
