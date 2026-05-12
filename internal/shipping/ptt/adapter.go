// Package ptt implements shipping.Adapter for PTT Kargo.
// Protocol: SOAP 1.1. Credentials are embedded in body elements (no WS-Security header).
// No webhook support — PTT does not offer push notifications.
// Default poll interval: 6h (PTT rate-limits aggressively).
package ptt

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"time"

	"github.com/mopro/platform/internal/shipping"
)

// Adapter implements shipping.Adapter for PTT Kargo.
type Adapter struct {
	cfg        shipping.PTTConfig
	httpClient *http.Client
}

// New constructs a PTT Adapter from config.
func New(cfg shipping.PTTConfig) *Adapter {
	return &Adapter{cfg: cfg, httpClient: &http.Client{Timeout: 30 * time.Second}}
}

// ── CalculateRate ─────────────────────────────────────────────────────────────

type rateReq struct {
	XMLName      xml.Name `xml:"CalculateRate"`
	Username     string   `xml:"Username"`
	Password     string   `xml:"Password"`
	CustomerCode string   `xml:"CustomerCode"`
	WeightGrams  int      `xml:"WeightGrams"`
}

type rateResp struct {
	XMLName    xml.Name `xml:"CalculateRateResponse"`
	TotalMinor int64    `xml:"TotalMinor"`
	Currency   string   `xml:"Currency"`
	EstDays    int      `xml:"EstimatedDays"`
}

func (a *Adapter) CalculateRate(ctx context.Context, req shipping.ShipmentInput) (shipping.RateResult, error) {
	body, err := xml.Marshal(rateReq{
		Username: a.cfg.Username, Password: a.cfg.Password,
		CustomerCode: a.cfg.CustomerCode, WeightGrams: req.WeightGrams,
	})
	if err != nil {
		return shipping.RateResult{}, err
	}
	var out rateResp
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, "CalculateRate", body, &out); err != nil {
		return shipping.RateResult{}, fmt.Errorf("ptt: CalculateRate: %w", err)
	}
	return shipping.RateResult{CostMinor: out.TotalMinor, Currency: out.Currency, EstimatedDays: out.EstDays, ServiceLevel: req.ServiceLevel}, nil
}

// ── CreateLabel ───────────────────────────────────────────────────────────────

func (a *Adapter) CreateLabel(ctx context.Context, req shipping.ShipmentInput) (shipping.ShipmentResult, error) {
	body, err := xml.Marshal(createLabelRequest{
		Username: a.cfg.Username, Password: a.cfg.Password,
		CustomerCode: a.cfg.CustomerCode, OrderID: req.OrderID,
		IdempotencyKey: req.IdempotencyKey, WeightGrams: req.WeightGrams,
	})
	if err != nil {
		return shipping.ShipmentResult{}, err
	}
	var out createLabelResponse
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, "CreateShipment", body, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("ptt: CreateLabel: %w", err)
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
	body, err := xml.Marshal(trackRequest{
		Username: a.cfg.Username, Password: a.cfg.Password,
		CustomerCode: a.cfg.CustomerCode, Barcode: trackingNumber,
	})
	if err != nil {
		return shipping.TrackResult{}, err
	}
	var out trackResponse
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, "TrackShipment", body, &out); err != nil {
		return shipping.TrackResult{}, fmt.Errorf("ptt: TrackShipment: %w", err)
	}
	return shipping.TrackResult{
		TrackingNumber: trackingNumber,
		State:          shipping.ShipmentState(mapPTTState(out.StatusCode)),
		Description:    out.Description,
		EventAt:        parsePTTDate(out.EventDate),
	}, nil
}

// ── CreateReturnLabel ─────────────────────────────────────────────────────────

type returnReq struct {
	XMLName    xml.Name `xml:"CreateReturn"`
	Username   string   `xml:"Username"`
	Password   string   `xml:"Password"`
	ShipmentID int64    `xml:"ShipmentID"`
}

func (a *Adapter) CreateReturnLabel(ctx context.Context, shipmentID int64) (shipping.ShipmentResult, error) {
	body, err := xml.Marshal(returnReq{Username: a.cfg.Username, Password: a.cfg.Password, ShipmentID: shipmentID})
	if err != nil {
		return shipping.ShipmentResult{}, err
	}
	var out createLabelResponse
	if err := doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, "CreateReturn", body, &out); err != nil {
		return shipping.ShipmentResult{}, fmt.Errorf("ptt: CreateReturnLabel: %w", err)
	}
	return shipping.ShipmentResult{TrackingNumber: out.TrackingNumber, CarrierShipmentID: out.CarrierShipmentID, LabelPDFBase64: out.LabelPDF}, nil
}

// ── CancelShipment ────────────────────────────────────────────────────────────

type cancelReq struct {
	XMLName        xml.Name `xml:"CancelShipment"`
	Username       string   `xml:"Username"`
	Password       string   `xml:"Password"`
	TrackingNumber string   `xml:"TrackingNumber"`
}

func (a *Adapter) CancelShipment(ctx context.Context, trackingNumber string) error {
	body, err := xml.Marshal(cancelReq{Username: a.cfg.Username, Password: a.cfg.Password, TrackingNumber: trackingNumber})
	if err != nil {
		return err
	}
	return doSOAP(ctx, a.httpClient, a.cfg.WSDLURL, "CancelShipment", body, nil)
}

// ── HandleWebhook ─────────────────────────────────────────────────────────────

// HandleWebhook always errors — PTT does not support push webhooks.
func (a *Adapter) HandleWebhook(_ context.Context, _ []byte, _ map[string]string) (shipping.WebhookEvent, error) {
	return shipping.WebhookEvent{}, fmt.Errorf("ptt: %w: carrier does not support webhooks", shipping.ErrInvalidSignature)
}
