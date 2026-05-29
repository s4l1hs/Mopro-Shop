package cashback

import (
	"encoding/json"
	"time"
)

// PlanStatus enumerates valid cashback_schema.plans.status values.
type PlanStatus string

const (
	PlanStatusActive    PlanStatus = "active"
	PlanStatusCompleted PlanStatus = "completed" // set atomically with the final installment
	PlanStatusCancelled PlanStatus = "cancelled" // refund / fraud — no new payments
)

// Plan is the in-memory representation of cashback_schema.plans.
// IMMUTABLE after creation except Status and PaymentsMade (CLAUDE.md § 4.7).
type Plan struct {
	ID                     int64
	OrderID                int64
	UserID                 int64
	PriceMinor             int64  // gross order price; drives ComputePlanTerms
	CommissionBps          int    // category commission in basis points; frozen at sale
	Currency               string // coin currency code, e.g. "TRY_COIN"
	TotalMonths            int    // frozen at creation via ComputePlanTerms
	MonthlyAmountMinor     int64  // regular installment; paid in months 1..TotalMonths-1
	MonthlyAmountLastMinor int64  // balloon payment in month TotalMonths; >= MonthlyAmountMinor
	// PaymentsMade is a DENORMALIZED CACHE of
	//   COUNT(*) FROM cashback_schema.payments WHERE plan_id=Plan.ID AND status='paid'.
	// The payments table is the source of truth (UNIQUE(plan_id, period_yyyymm) is the
	// cron's idempotency guard). The cache is refreshed atomically by
	// RefreshPaymentsMadeCache inside the SERIALIZABLE tx that flips each payment
	// row to 'paid'. Do NOT treat as authoritative for audit / reconcile /
	// partial-refund flows — count the payments table directly.
	PaymentsMade int
	// ReferenceInterestRateBps is a v6 legacy field kept for backward compat with the HTTP API;
	// always 0 for v8 plans. Do not use in business logic.
	ReferenceInterestRateBps int
	Status                   PlanStatus
	StartDate                time.Time
	DeliveredAt              time.Time
	Market                   string
	CommissionSnapshot       json.RawMessage // audit JSONB from the order event
	IdempotencyKey           string
	// Product snapshot from Phase 4.4a; nil/empty for pre-4.4a plans.
	ProductID       int64
	ProductTitle    string
	ProductImageURL string
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// PlanTerms is defined in calculator.go — referenced here for documentation only.

// Payment is the in-memory representation of cashback_schema.payments (v6 legacy; read-only in v8).
type Payment struct {
	ID                  int64
	PlanID              int64
	PeriodYYYYMM        int
	ScheduledDate       time.Time
	PaidDate            *time.Time
	AmountMinor         int64
	Status              string
	LedgerTransactionID *int64
	IdempotencyKey      string
	AttemptCount        int
	LastAttemptAt       *time.Time
	LastError           *string
	CreatedAt           time.Time
}

// PaymentSummary summarises a PayMonthlyInstallments run.
type PaymentSummary struct {
	Processed int // plans for which an installment was paid this run
	Skipped   int // plans skipped (wallet frozen, not yet due, etc.)
	Failed    int // plans that errored after retries
	Retries   int // total SERIALIZABLE retry count across all plans
}

// CommissionSnapshotItem records per-item commission details frozen at order time.
// Stored as JSONB in cashback_schema.plans.commission_snapshot for audit.
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
