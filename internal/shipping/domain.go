// Package shipping manages carrier integrations behind a single provider-agnostic
// interface. The active carriers are configured by env at startup.
// ARCHITECTURE.md § 8.4.
package shipping

import "time"

// ShipmentState is the lifecycle state of a shipment.
type ShipmentState string

const (
	ShipmentStatePending        ShipmentState = "pending"
	ShipmentStatePickedUp       ShipmentState = "picked_up"
	ShipmentStateInTransit      ShipmentState = "in_transit"
	ShipmentStateOutForDelivery ShipmentState = "out_for_delivery"
	ShipmentStateDelivered      ShipmentState = "delivered"
	ShipmentStateReturned       ShipmentState = "returned"
	ShipmentStateCancelled      ShipmentState = "cancelled"
	ShipmentStateFailed         ShipmentState = "failed"
)

// Shipment is the entity persisted in shipping_schema.shipments.
type Shipment struct {
	ID                  int64
	OrderID             int64
	Carrier             string
	TrackingNumber      string
	CarrierShipmentID   string
	State               ShipmentState
	LabelPDFB2Key       string
	EstimatedDeliveryAt *time.Time
	DeliveredAt         *time.Time
	LastPolledAt        *time.Time
	IdempotencyKey      string
	CostMinor           int64
	CostCurrency        string
	CreatedAt           time.Time
	UpdatedAt           time.Time
}

// ShipmentEvent is one state-transition row in shipping_schema.shipment_events.
type ShipmentEvent struct {
	ID         int64
	ShipmentID int64
	State      ShipmentState
	Source     string // "webhook" | "poll" | "api"
	CarrierRaw []byte
	EventAt    time.Time
}

// WebhookEvent is the normalised result from parsing a carrier push notification.
// Produced by Adapter.HandleWebhook after signature validation.
type WebhookEvent struct {
	TrackingNumber string
	State          ShipmentState
	Description    string
	EventAt        time.Time
	CarrierRaw     []byte
}

// ShipmentInput is the provider-agnostic label creation request.
type ShipmentInput struct {
	OrderID            int64
	IdempotencyKey     string
	Carrier            string
	SellerAddressRef   int64
	BuyerAddressRef    int64
	WeightGrams        int
	LengthCM           int
	WidthCM            int
	HeightCM           int
	DeclaredValueMinor int64
	DeclaredValueCurr  string
	ServiceLevel       string // "standard" | "express"
	InsuranceWanted    bool
	CashOnDelivery     bool
	Notes              string
}

// ShipmentResult is returned by CreateLabel.
type ShipmentResult struct {
	TrackingNumber    string
	CarrierShipmentID string
	LabelPDFBase64    string
	EstimatedDelivery *time.Time
	CostMinor         int64
	CostCurrency      string
}

// TrackResult is returned by TrackShipment (poll path).
type TrackResult struct {
	TrackingNumber string
	State          ShipmentState
	Description    string
	EventAt        time.Time
	CarrierRaw     []byte
}

// RateResult is returned by CalculateRate.
type RateResult struct {
	CostMinor     int64
	Currency      string
	EstimatedDays int
	ServiceLevel  string
}

// ETAResult is a pre-purchase delivery-time estimate in transit business days,
// returned by EstimateETA. MaxDays == 0 means "no estimate available" (no transit
// data and no national fallback for the market) — callers should omit the line.
// Confident is false when the value came from the conservative national fallback
// (unknown origin/dest) rather than a concrete origin×dest transit row; the UI
// surfaces low-confidence estimates with a clearer "tahmini" hedge (§9: no SLA promise).
type ETAResult struct {
	MinDays   int
	MaxDays   int
	Confident bool
}

// Config aggregates all carrier configurations.
// Carriers with missing fields are skipped in non-production; fatal in production
// if they are KARGO_DEFAULT.
type Config struct {
	Default  string
	Aras     ArasConfig
	Yurtici  YurticiConfig
	Surat    SuratConfig
	MNG      MNGConfig
	HepsiJet HepsiJetConfig
	PTT      PTTConfig
}

// ArasConfig holds Aras Kargo REST API credentials.
type ArasConfig struct {
	BaseURL      string
	Username     string
	Password     string
	CustomerCode string
}

// YurticiConfig holds Yurtiçi Kargo SOAP credentials.
type YurticiConfig struct {
	WSDLURL      string
	Username     string
	Password     string
	CustomerCode string
}

// SuratConfig holds Sürat Kargo REST API credentials.
type SuratConfig struct {
	BaseURL       string
	Username      string
	Password      string
	WebhookSecret string
}

// MNGConfig holds MNG Kargo REST API credentials.
type MNGConfig struct {
	BaseURL       string
	APIKey        string
	WebhookSecret string
}

// HepsiJetConfig holds HepsiJet REST API credentials.
type HepsiJetConfig struct {
	BaseURL      string
	ClientID     string
	ClientSecret string
	WebhookToken string
}

// PTTConfig holds PTT Kargo SOAP credentials.
type PTTConfig struct {
	WSDLURL      string
	Username     string
	Password     string
	CustomerCode string
}
