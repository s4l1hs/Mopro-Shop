package orderledger

import "time"

// PaidItem mirrors one frozen order_items row from the ecom.order.paid.v1 payload.
type PaidItem struct {
	VariantID             int64 `json:"variant_id"`
	SellerID              int64 `json:"seller_id"`
	Qty                   int   `json:"qty"`
	UnitPriceMinor        int64 `json:"unit_price_minor"`
	CommissionPctBps      int   `json:"commission_pct_bps"`
	KdvPctBps             int   `json:"kdv_pct_bps"`
	CommissionAmountMinor int64 `json:"commission_amount_minor"`
	KdvAmountMinor        int64 `json:"kdv_amount_minor"`
	SellerNetMinor        int64 `json:"seller_net_minor"`
}

// OrderPaidEvent is parsed from the ecom.order.paid.v1 Redis Streams message.
type OrderPaidEvent struct {
	OrderID       int64
	UserID        int64
	SellerID      int64
	PaidAt        time.Time
	GrossMinor    int64 // = order.total_minor (PSP capture amount)
	ShippingMinor int64
	Currency      string
	Market        string
	Items         []PaidItem
}

// CaptureInputs is the normalized, aggregated input to Compute().
// Derived from OrderPaidEvent by summing item-level frozen snapshots.
type CaptureInputs struct {
	OrderID         int64
	SellerID        int64
	GrossMinor      int64 // PSP capture = order.total_minor
	SellerNetMinor  int64 // sum(item.seller_net_minor)
	CommissionMinor int64 // sum(item.commission_amount_minor), used for audit column only
	KdvMinor        int64 // sum(item.kdv_amount_minor)
	ShippingMinor   int64 // order.shipping_minor
	Currency        string
	Market          string
}

// LedgerLine is one debit or credit in the balanced capture posting.
type LedgerLine struct {
	AccountType string // e.g. "asset:psp_receivable"
	SellerID    int64  // non-zero only for liability:seller_payable entries
	Direction   string // "D" or "C"
	AmountMinor int64  // always > 0
}

// CaptureEntries is the balanced result from Compute().
// Invariant: sum(D amounts) == sum(C amounts) == GrossMinor.
// Zero-amount lines (e.g. zero shipping) are excluded.
type CaptureEntries struct {
	Lines []LedgerLine
}

// The CapturePosting audit-row struct moved to internal/commission as part
// of the commission-owns-capture-postings refactor. orderledger.Service
// now persists postings through the commission.CaptureRecorder seam;
// callers wanting the struct should import commission.CapturePosting.
