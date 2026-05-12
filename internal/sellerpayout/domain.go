package sellerpayout

import "time"

// PayoutStatus enumerates valid commission_schema.seller_payouts.status values.
type PayoutStatus string

const (
	PayoutStatusScheduled   PayoutStatus = "scheduled"
	PayoutStatusProcessing  PayoutStatus = "processing"
	PayoutStatusPaid        PayoutStatus = "paid"
	PayoutStatusFailed      PayoutStatus = "failed"
	PayoutStatusCancelled   PayoutStatus = "cancelled"
	PayoutStatusReversed    PayoutStatus = "reversed"
)

// Payout is the in-memory representation of commission_schema.seller_payouts.
// amount_minor and unlock_at are IMMUTABLE once created (CLAUDE.md § 4.8).
type Payout struct {
	ID             int64
	OrderID        int64
	SellerID       int64
	AmountMinor    int64
	Currency       string
	DeliveredAt    time.Time
	UnlockAt       time.Time
	PaidAt         *time.Time
	Status         PayoutStatus
	Market         string
	IdempotencyKey string
	CreatedAt      time.Time
	UpdatedAt      time.Time
}
