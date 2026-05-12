package order

import "time"

// OrderStatus represents the order lifecycle state.
type OrderStatus string

const (
	StatusPendingPayment    OrderStatus = "pending_payment"
	StatusPaid              OrderStatus = "paid"
	StatusShipped           OrderStatus = "shipped"
	StatusDelivered         OrderStatus = "delivered"
	StatusCancelled         OrderStatus = "cancelled"
	StatusRefunded          OrderStatus = "refunded"
	StatusPartiallyRefunded OrderStatus = "partially_refunded"
)

// Order is the aggregate root for a customer purchase.
type Order struct {
	ID               int64       `json:"id"`
	UserID           int64       `json:"user_id"`
	Status           OrderStatus `json:"status"`
	SubtotalMinor    int64       `json:"subtotal_minor"`
	ShippingMinor    int64       `json:"shipping_minor"`
	ShippingPayer    string      `json:"shipping_payer"`
	TotalMinor       int64       `json:"total_minor"`
	Currency         string      `json:"currency"`
	Market           string      `json:"market"`
	DeliveredAt      *time.Time  `json:"delivered_at,omitempty"`
	CashbackEligible bool        `json:"cashback_eligible"`
	CashbackCurrency string      `json:"cashback_currency"`
	IdempotencyKey   string      `json:"idempotency_key"`
	CreatedAt        time.Time   `json:"created_at"`
	UpdatedAt        time.Time   `json:"updated_at"`
}

// OrderItem is a single line in the order with frozen commission snapshots.
// Snapshots are set at order time and NEVER recomputed.
type OrderItem struct {
	ID                    int64  `json:"id"`
	OrderID               int64  `json:"order_id"`
	VariantID             int64  `json:"variant_id"`
	SellerID              int64  `json:"seller_id"`
	CategoryID            int64  `json:"category_id"`
	Qty                   int    `json:"qty"`
	UnitPriceMinor        int64  `json:"unit_price_minor"`
	UnitPriceCurrency     string `json:"unit_price_currency"`
	CommissionPctBps      int    `json:"commission_pct_bps"`
	KdvPctBps             int    `json:"kdv_pct_bps"`
	CommissionAmountMinor int64  `json:"commission_amount_minor"`
	KdvAmountMinor        int64  `json:"kdv_amount_minor"`
	SellerNetMinor        int64  `json:"seller_net_minor"`
}

// CheckoutRequest is the input for Service.Checkout.
type CheckoutRequest struct {
	UserID         int64
	ReservationID  string // from cart.Reserve; empty tolerated on idempotent retries
	Market         string // overrides service default when non-empty
	Currency       string // overrides first-item currency when non-empty
	IdempotencyKey string
}
