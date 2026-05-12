// Package mng implements shipping.Adapter for MNG Kargo.
// Authentication: X-API-Key header.
// Webhook signature: X-MNG-Signature = hex(HMAC-SHA256(rawBody, webhookSecret)).
package mng

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

// Adapter implements shipping.Adapter for MNG Kargo.
type Adapter struct {
	cfg    shipping.MNGConfig
	client *client
}

// New constructs an MNG Adapter from config.
func New(cfg shipping.MNGConfig) *Adapter {
	return &Adapter{cfg: cfg, client: newClient(cfg.BaseURL, cfg.APIKey)}
}

var stateMap = map[string]shipping.ShipmentState{
	"KABUL":       shipping.ShipmentStatePickedUp,
	"TRANSFER":    shipping.ShipmentStateInTransit,
	"DAGITIMDA":   shipping.ShipmentStateOutForDelivery,
	"TESLIM":      shipping.ShipmentStateDelivered,
	"IADE":        shipping.ShipmentStateReturned,
	"IPTAL":       shipping.ShipmentStateCancelled,
}

func mapState(raw string) shipping.ShipmentState {
	if s, ok := stateMap[raw]; ok {
		return s
	}
	return shipping.ShipmentStateInTransit
}

// ── CalculateRate ─────────────────────────────────────────────────────────────

type rateReq struct {
	WeightGrams int    `json:"weight_grams"`
	ServiceCode string `json:"service_code"`
}

type rateResp struct {
	TotalMinor int64  `json:"total_minor"`
	Currency   string `json:"currency"`
	EstDays    int    `json:"estimated_days"`
}

func (a *Adapter) CalculateRate(ctx context.Context, req shipping.ShipmentInput) (shipping.RateResult, error) {
	var out rateResp
	if err := a.client.do(ctx, http.MethodPost, "/v1/rate", rateReq{WeightGrams: req.WeightGrams, ServiceCode: req.ServiceLevel}, &out); err != nil {
		return shipping.RateResult{}, fmt.Errorf("mng: CalculateRate: %w", err)
	}
	return shipping.RateResult{CostMinor: out.TotalMinor, Currency: out.Currency, EstimatedDays: out.EstDays, ServiceLevel: req.ServiceLevel}, nil
}

// ── CreateLabel ───────────────────────────────────────────────────────────────

type labelReq struct {
	OrderID        int64  `json:"order_id"`
	IdempotencyKey string `json:"idempotency_key"`
	WeightGrams    int    `json:"weight_grams"`
}

type labelResp struct {
	TrackingNumber    string `json:"tracking_number"`
	CarrierShipmentID string `json:"shipment_id"`
	LabelPDF          string `json:"label_pdf_base64"`
	CostMinor         int64  `json:"cost_minor"`
	Currency          string `json:"currency"`
}

func (a *Adapter) CreateLabel(ctx context.Context, req shipping.ShipmentInput) (shipping.ShipmentResult, error) {
	var out labelResp
	if err := a.client.do(ctx, http.MethodPost, "/v1/shipment", labelReq{OrderID: req.OrderID, IdempotencyKey: req.IdempotencyKey, WeightGrams: req.WeightGrams}, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("mng: CreateLabel: %w", err)
	}
	return shipping.ShipmentResult{TrackingNumber: out.TrackingNumber, CarrierShipmentID: out.CarrierShipmentID, LabelPDFBase64: out.LabelPDF, CostMinor: out.CostMinor, CostCurrency: out.Currency}, nil
}

// ── TrackShipment ─────────────────────────────────────────────────────────────

type trackResp struct {
	StatusCode  string `json:"status_code"`
	Description string `json:"description"`
	EventAt     string `json:"event_at"`
}

func (a *Adapter) TrackShipment(ctx context.Context, trackingNumber string) (shipping.TrackResult, error) {
	var out trackResp
	if err := a.client.do(ctx, http.MethodGet, "/v1/shipment/"+trackingNumber+"/status", nil, &out); err != nil {
		return shipping.TrackResult{}, fmt.Errorf("mng: TrackShipment: %w", err)
	}
	eventAt, _ := time.Parse(time.RFC3339, out.EventAt)
	return shipping.TrackResult{TrackingNumber: trackingNumber, State: mapState(out.StatusCode), Description: out.Description, EventAt: eventAt}, nil
}

// ── CreateReturnLabel ─────────────────────────────────────────────────────────

func (a *Adapter) CreateReturnLabel(ctx context.Context, shipmentID int64) (shipping.ShipmentResult, error) {
	var out labelResp
	if err := a.client.do(ctx, http.MethodPost, fmt.Sprintf("/v1/shipment/%d/return", shipmentID), nil, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("mng: CreateReturnLabel: %w", err)
	}
	return shipping.ShipmentResult{TrackingNumber: out.TrackingNumber, CarrierShipmentID: out.CarrierShipmentID, LabelPDFBase64: out.LabelPDF}, nil
}

// ── CancelShipment ────────────────────────────────────────────────────────────

func (a *Adapter) CancelShipment(ctx context.Context, trackingNumber string) error {
	return a.client.do(ctx, http.MethodDelete, "/v1/shipment/"+trackingNumber, nil, nil)
}

// ── HandleWebhook ─────────────────────────────────────────────────────────────

type webhookPayload struct {
	TrackingNumber string `json:"tracking_number"`
	StatusCode     string `json:"status_code"`
	Description    string `json:"description"`
	EventAt        string `json:"event_at"`
}

// HandleWebhook validates X-MNG-Signature: hex(HMAC-SHA256(body, secret)) and parses.
func (a *Adapter) HandleWebhook(_ context.Context, rawBody []byte, headers map[string]string) (shipping.WebhookEvent, error) {
	sig := headers["X-MNG-Signature"]
	if !validHMAC(rawBody, a.cfg.WebhookSecret, sig) {
		return shipping.WebhookEvent{}, shipping.ErrInvalidSignature
	}
	var p webhookPayload
	if err := json.Unmarshal(rawBody, &p); err != nil {
		return shipping.WebhookEvent{}, fmt.Errorf("mng: webhook decode: %w", err)
	}
	eventAt, _ := time.Parse(time.RFC3339, p.EventAt)
	return shipping.WebhookEvent{
		TrackingNumber: p.TrackingNumber,
		State:          mapState(p.StatusCode),
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
