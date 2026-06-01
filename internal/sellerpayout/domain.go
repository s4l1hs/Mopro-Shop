package sellerpayout

import "time"

// PayoutStatus enumerates valid sellerpayout_schema.seller_payouts.status values.
type PayoutStatus string

const (
	PayoutStatusScheduled  PayoutStatus = "scheduled"
	PayoutStatusProcessing PayoutStatus = "processing"
	PayoutStatusPaid       PayoutStatus = "paid"
	PayoutStatusFailed     PayoutStatus = "failed"
	PayoutStatusCancelled  PayoutStatus = "cancelled"
	PayoutStatusReversed   PayoutStatus = "reversed"
)

// BatchStatus enumerates valid sellerpayout_schema.payout_batches.status values.
type BatchStatus string

const (
	BatchStatusPending    BatchStatus = "pending"
	BatchStatusProcessing BatchStatus = "processing"
	BatchStatusPaid       BatchStatus = "paid"
	BatchStatusFailed     BatchStatus = "failed"
	BatchStatusAmbiguous  BatchStatus = "ambiguous"
	BatchStatusCancelled  BatchStatus = "cancelled"
)

// Payout is the in-memory representation of sellerpayout_schema.seller_payouts.
// amount_minor and unlock_at are IMMUTABLE once created (CLAUDE.md § 4.8).
type Payout struct {
	ID                  int64
	OrderID             int64
	SellerID            int64
	AmountMinor         int64
	Currency            string
	DeliveredAt         time.Time
	UnlockAt            time.Time
	PaidAt              *time.Time
	PspTransferID       string
	LedgerTransactionID *int64
	Status              PayoutStatus
	Market              string
	IdempotencyKey      string
	BatchID             *int64
	AttemptCount        int
	LastAttemptAt       *time.Time
	LastError           string
	CreatedAt           time.Time
	UpdatedAt           time.Time
}

// PayoutBatch aggregates all seller_payouts for one (seller_id, currency, payout_date).
// One Sipay transfer per batch; idempotency_key = "payout:seller_{id}:date_{YYYYMMDD}:ccy_{CCY}".
type PayoutBatch struct {
	ID                  int64
	SellerID            int64
	Currency            string
	PayoutDate          time.Time
	TotalAmountMinor    int64
	PspTransferID       string
	Status              BatchStatus
	LedgerTransactionID *int64
	PaidAt              *time.Time
	IdempotencyKey      string
	AttemptCount        int
	LastAttemptAt       *time.Time
	LastError           string
	Market              string
	CreatedAt           time.Time
	UpdatedAt           time.Time
}

// SellerPspAccount holds fin-svc-side PSP registration for a seller.
// Populated by consuming ecom.seller.psp_onboarded.v1 from Redis Streams.
type SellerPspAccount struct {
	ID          int64
	SellerID    int64
	PspMemberID string
	Market      string
	Status      string
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

// TransferRequest is the input to PspTransferer.Transfer.
type TransferRequest struct {
	BatchID        int64
	PspMemberID    string
	AmountMinor    int64
	Currency       string
	IdempotencyKey string
	Market         string
}

// TransferResponse is the output from PspTransferer.Transfer and GetTransferStatus.
type TransferResponse struct {
	TransferID string
	Status     string // "paid", "pending", "failed"
	ErrorMsg   string
}

// RunDailyResult summarises one run of RunDailyPayouts.
type RunDailyResult struct {
	PayoutDate   time.Time
	Currency     string
	Batched      int // batches created and submitted
	Paid         int // batches confirmed paid (live or shadow)
	Shadow       int // batches paid via shadow mode
	Failed       int // batches that hit an unrecoverable error
	Skipped      int // idempotent re-runs
	Ambiguous    int // PSP returned unexpected state; see ledger_alerts
	TotalRetries int
}

// LedgerAlert is a row to be inserted into wallet_schema.ledger_alerts.
type LedgerAlert struct {
	Severity  string // 'CRITICAL','SEV1','SEV2','SEV3'
	Currency  string
	BatchID   *int64
	AlertType string
	Message   string
}

// PspOnboardedEvent is the decoded payload of ecom.seller.psp_onboarded.v1.
type PspOnboardedEvent struct {
	SellerID    int64
	PspMemberID string
	Market      string
}

// FraudHoldSetEvent is the decoded payload of ecom.seller.fraud_hold_set.v1.
type FraudHoldSetEvent struct {
	SellerID int64
	Market   string
	Currency string
	Reason   string
}
