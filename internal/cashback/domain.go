package cashback

import (
	"encoding/json"
	"time"
)

// CommissionSnapshotItem records the per-item commission breakdown frozen at order time.
// Stored as JSONB in cashback_schema.plans.commission_snapshot for audit purposes.
type CommissionSnapshotItem struct {
	VariantID             int64 `json:"variant_id"`
	SellerID              int64 `json:"seller_id"`
	CategoryID            int64 `json:"category_id"`
	Qty                   int   `json:"qty"`
	UnitPriceMinor        int64 `json:"unit_price_minor"`
	CommissionPctBps      int   `json:"commission_pct_bps"`
	KdvPctBps             int   `json:"kdv_pct_bps"`
	CommissionAmountMinor int64 `json:"commission_amount_minor"`
	KdvAmountMinor        int64 `json:"kdv_amount_minor"`
	SellerNetMinor        int64 `json:"seller_net_minor"`
}

// PlanStatus enumerates valid cashback_schema.plans.status values.
type PlanStatus string

const (
	PlanStatusActive    PlanStatus = "active"
	PlanStatusCancelled PlanStatus = "cancelled"
	PlanStatusSuspended PlanStatus = "suspended"
)

// Plan is the in-memory representation of cashback_schema.plans.
// IMMUTABLE after creation except Status (CLAUDE.md § 4.7).
type Plan struct {
	ID                       int64
	OrderID                  int64
	UserID                   int64
	MonthlyAmountMinor       int64
	Currency                 string
	ReferenceInterestRateBps int
	StartDate                time.Time
	Status                   PlanStatus
	DeliveredAt              time.Time
	Market                   string
	CommissionSnapshot       json.RawMessage
	IdempotencyKey           string
	CreatedAt                time.Time
	UpdatedAt                time.Time
}
