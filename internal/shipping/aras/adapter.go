// Package aras implements shipping.Adapter for Aras Kargo (REST, polling-only).
// Authentication: Basic Auth (username:password base64) on every request.
// No webhook support — carrier does not offer push notifications.
package aras

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/mopro/platform/internal/shipping"
)

// Adapter implements shipping.Adapter for Aras Kargo.
type Adapter struct {
	baseURL      string
	customerCode string
	basicAuth    string
	httpClient   *http.Client
}

// New constructs an Aras Adapter from config.
func New(cfg shipping.ArasConfig) *Adapter {
	creds := base64.StdEncoding.EncodeToString([]byte(cfg.Username + ":" + cfg.Password))
	return &Adapter{
		baseURL:      cfg.BaseURL,
		customerCode: cfg.CustomerCode,
		basicAuth:    "Basic " + creds,
		httpClient:   &http.Client{Timeout: 15 * time.Second},
	}
}

var stateMap = map[string]shipping.ShipmentState{
	"1": shipping.ShipmentStatePickedUp,
	"2": shipping.ShipmentStateInTransit,
	"3": shipping.ShipmentStateOutForDelivery,
	"4": shipping.ShipmentStateDelivered,
	"5": shipping.ShipmentStateReturned,
	"6": shipping.ShipmentStateCancelled,
}

func mapState(code string) shipping.ShipmentState {
	if s, ok := stateMap[code]; ok {
		return s
	}
	return shipping.ShipmentStateInTransit
}

func (a *Adapter) do(ctx context.Context, method, path string, in, out any) error {
	var body *bytes.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return err
		}
		body = bytes.NewReader(b)
	} else {
		body = bytes.NewReader(nil)
	}
	req, err := http.NewRequestWithContext(ctx, method, a.baseURL+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", a.basicAuth)
	req.Header.Set("Content-Type", "application/json")
	resp, err := a.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("aras: %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("aras: %s %s status %d", method, path, resp.StatusCode)
	}
	if out != nil {
		return json.NewDecoder(resp.Body).Decode(out)
	}
	return nil
}

// ── CalculateRate ─────────────────────────────────────────────────────────────

type rateReq struct {
	CustomerCode string `json:"customerCode"`
	WeightGrams  int    `json:"weightGrams"`
}

type rateResp struct {
	TotalMinor int64  `json:"totalMinor"`
	Currency   string `json:"currency"`
	EstDays    int    `json:"estimatedDays"`
}

func (a *Adapter) CalculateRate(ctx context.Context, req shipping.ShipmentInput) (shipping.RateResult, error) {
	var out rateResp
	if err := a.do(ctx, http.MethodPost, "/api/v1/rate", rateReq{CustomerCode: a.customerCode, WeightGrams: req.WeightGrams}, &out); err != nil {
		return shipping.RateResult{}, fmt.Errorf("aras: CalculateRate: %w", err)
	}
	return shipping.RateResult{CostMinor: out.TotalMinor, Currency: out.Currency, EstimatedDays: out.EstDays, ServiceLevel: req.ServiceLevel}, nil
}

// ── CreateLabel ───────────────────────────────────────────────────────────────

type labelReq struct {
	CustomerCode   string `json:"customerCode"`
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
	if err := a.do(ctx, http.MethodPost, "/api/v1/shipment",
		labelReq{CustomerCode: a.customerCode, OrderID: req.OrderID, IdempotencyKey: req.IdempotencyKey, WeightGrams: req.WeightGrams}, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("aras: CreateLabel: %w", err)
	}
	return shipping.ShipmentResult{TrackingNumber: out.TrackingNumber, CarrierShipmentID: out.CarrierShipmentID, LabelPDFBase64: out.LabelPDF, CostMinor: out.CostMinor, CostCurrency: out.Currency}, nil
}

// ── TrackShipment ─────────────────────────────────────────────────────────────

type trackResp struct {
	StatusCode  string `json:"statusCode"`
	Description string `json:"description"`
	EventAt     string `json:"eventAt"`
}

func (a *Adapter) TrackShipment(ctx context.Context, trackingNumber string) (shipping.TrackResult, error) {
	var out trackResp
	if err := a.do(ctx, http.MethodGet, "/api/v1/shipment/"+trackingNumber, nil, &out); err != nil {
		return shipping.TrackResult{}, fmt.Errorf("aras: TrackShipment: %w", err)
	}
	eventAt, _ := time.Parse(time.RFC3339, out.EventAt)
	return shipping.TrackResult{TrackingNumber: trackingNumber, State: mapState(out.StatusCode), Description: out.Description, EventAt: eventAt}, nil
}

// ── CreateReturnLabel ─────────────────────────────────────────────────────────

func (a *Adapter) CreateReturnLabel(ctx context.Context, shipmentID int64) (shipping.ShipmentResult, error) {
	var out labelResp
	if err := a.do(ctx, http.MethodPost, fmt.Sprintf("/api/v1/shipment/%d/return", shipmentID), nil, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("aras: CreateReturnLabel: %w", err)
	}
	return shipping.ShipmentResult{TrackingNumber: out.TrackingNumber, CarrierShipmentID: out.CarrierShipmentID, LabelPDFBase64: out.LabelPDF}, nil
}

// ── CancelShipment ────────────────────────────────────────────────────────────

func (a *Adapter) CancelShipment(ctx context.Context, trackingNumber string) error {
	return a.do(ctx, http.MethodDelete, "/api/v1/shipment/"+trackingNumber, nil, nil)
}

// ── HandleWebhook ─────────────────────────────────────────────────────────────

// HandleWebhook always returns ErrInvalidSignature — Aras does not support push webhooks.
func (a *Adapter) HandleWebhook(_ context.Context, _ []byte, _ map[string]string) (shipping.WebhookEvent, error) {
	return shipping.WebhookEvent{}, fmt.Errorf("aras: %w: carrier does not support webhooks", shipping.ErrInvalidSignature)
}
