// Package yurtici implements shipping.Adapter for Yurtiçi Kargo.
// Protocol: SOAP 1.1 with WS-Security UsernameToken header (no webhook support).
// All XML serialisation uses stdlib encoding/xml — no external dependencies.
package yurtici

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"time"

	"github.com/mopro/platform/internal/shipping"
)

// Adapter implements shipping.Adapter for Yurtiçi Kargo.
type Adapter struct {
	cfg        shipping.YurticiConfig
	httpClient *http.Client
}

// New constructs a Yurtiçi Adapter from config.
func New(cfg shipping.YurticiConfig) *Adapter {
	return &Adapter{cfg: cfg, httpClient: &http.Client{Timeout: 20 * time.Second}}
}

// ── CalculateRate ─────────────────────────────────────────────────────────────

type rateRequestBody struct {
	XMLName      xml.Name `xml:"CalculateRate"`
	WeightGrams  int      `xml:"WeightGrams"`
	CustomerCode string   `xml:"CustomerCode"`
}

type rateResponseBody struct {
	XMLName    xml.Name `xml:"CalculateRateResponse"`
	TotalMinor int64    `xml:"TotalMinor"`
	Currency   string   `xml:"Currency"`
	EstDays    int      `xml:"EstimatedDays"`
}

func (a *Adapter) CalculateRate(ctx context.Context, req shipping.ShipmentInput) (shipping.RateResult, error) {
	body, err := xml.Marshal(rateRequestBody{WeightGrams: req.WeightGrams, CustomerCode: a.cfg.CustomerCode})
	if err != nil {
		return shipping.RateResult{}, err
	}
	var out rateResponseBody
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, a.cfg.Username, a.cfg.Password, "CalculateRate", body, &out); err != nil {
		return shipping.RateResult{}, fmt.Errorf("yurtici: CalculateRate: %w", err)
	}
	return shipping.RateResult{CostMinor: out.TotalMinor, Currency: out.Currency, EstimatedDays: out.EstDays, ServiceLevel: req.ServiceLevel}, nil
}

// ── CreateLabel ───────────────────────────────────────────────────────────────

func (a *Adapter) CreateLabel(ctx context.Context, req shipping.ShipmentInput) (shipping.ShipmentResult, error) {
	body, err := xml.Marshal(createLabelRequest{
		CustomerCode:   a.cfg.CustomerCode,
		OrderID:        req.OrderID,
		IdempotencyKey: req.IdempotencyKey,
		WeightGrams:    req.WeightGrams,
	})
	if err != nil {
		return shipping.ShipmentResult{}, err
	}
	var out createLabelResponse
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, a.cfg.Username, a.cfg.Password, "CreateShipment", body, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("yurtici: CreateLabel: %w", err)
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

func (a *Adapter) TrackShipment(ctx context.Context, trackingNumber string) (shipping.TrackResult, error) {
	body, err := xml.Marshal(trackRequest{QueryNumber: trackingNumber, CustomerCode: a.cfg.CustomerCode})
	if err != nil {
		return shipping.TrackResult{}, err
	}
	var out trackResponse
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, a.cfg.Username, a.cfg.Password, "TrackShipment", body, &out); err != nil {
		return shipping.TrackResult{}, fmt.Errorf("yurtici: TrackShipment: %w", err)
	}
	stateStr := shipping.ShipmentState(mapYurticiState(out.StatusCode))
	return shipping.TrackResult{
		TrackingNumber: trackingNumber,
		State:          stateStr,
		Description:    out.Description,
		EventAt:        parseYurticiDate(out.EventDate),
	}, nil
}

// ── CreateReturnLabel ─────────────────────────────────────────────────────────

type returnRequest struct {
	XMLName    xml.Name `xml:"CreateReturn"`
	ShipmentID int64    `xml:"ShipmentID"`
}

func (a *Adapter) CreateReturnLabel(ctx context.Context, shipmentID int64) (shipping.ShipmentResult, error) {
	body, err := xml.Marshal(returnRequest{ShipmentID: shipmentID})
	if err != nil {
		return shipping.ShipmentResult{}, err
	}
	var out createLabelResponse
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, a.cfg.Username, a.cfg.Password, "CreateReturn", body, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("yurtici: CreateReturnLabel: %w", err)
	}
	return shipping.ShipmentResult{TrackingNumber: out.TrackingNumber, CarrierShipmentID: out.CarrierShipmentID, LabelPDFBase64: out.LabelPDF}, nil
}

// ── CancelShipment ────────────────────────────────────────────────────────────

type cancelRequest struct {
	XMLName        xml.Name `xml:"CancelShipment"`
	TrackingNumber string   `xml:"TrackingNumber"`
}

func (a *Adapter) CancelShipment(ctx context.Context, trackingNumber string) error {
	body, err := xml.Marshal(cancelRequest{TrackingNumber: trackingNumber})
	if err != nil {
		return err
	}
	return doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, a.cfg.Username, a.cfg.Password, "CancelShipment", body, nil)
}

// ── HandleWebhook ─────────────────────────────────────────────────────────────

// HandleWebhook always errors — Yurtiçi does not support push webhooks.
func (a *Adapter) HandleWebhook(_ context.Context, _ []byte, _ map[string]string) (shipping.WebhookEvent, error) {
	return shipping.WebhookEvent{}, fmt.Errorf("yurtici: %w: carrier does not support webhooks", shipping.ErrInvalidSignature)
}
