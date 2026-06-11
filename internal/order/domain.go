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
	ID                int64       `json:"id"`
	UserID            int64       `json:"user_id"`
	SellerID          int64       `json:"seller_id,omitempty"`           // 0 = legacy single-order
	CheckoutSessionID string      `json:"checkout_session_id,omitempty"` // "" = legacy single-order
	Status            OrderStatus `json:"status"`
	SubtotalMinor     int64       `json:"subtotal_minor"`
	ShippingMinor     int64       `json:"shipping_minor"`
	ShippingPayer     string      `json:"shipping_payer"`
	// DiscountMinor is the total seller-funded basket discount applied across all
	// items (CT-09): Σ(list_unit − unit)×qty. SubtotalMinor is pre-discount;
	// TotalMinor = SubtotalMinor − DiscountMinor (the charged amount). 0 when no
	// item carries a basket discount → SubtotalMinor == TotalMinor.
	DiscountMinor    int64      `json:"discount_minor"`
	// CouponCode is the applied coupon (empty = none) and CouponDiscountMinor is its
	// slice of DiscountMinor (CT-03/CHK-04). The remainder of DiscountMinor is the
	// CT-09 basket discount. Coupon is seller-funded ⇒ folded into the same snapshot.
	CouponCode          string     `json:"coupon_code,omitempty"`
	CouponDiscountMinor int64      `json:"coupon_discount_minor"`
	TotalMinor          int64      `json:"total_minor"`
	Currency            string     `json:"currency"`
	Market              string     `json:"market"`
	DeliveredAt      *time.Time `json:"delivered_at,omitempty"`
	CashbackEligible bool       `json:"cashback_eligible"`
	CashbackCurrency string     `json:"cashback_currency"`
	IdempotencyKey   string     `json:"idempotency_key"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

// OrderItem is a single line in the order with frozen commission snapshots.
// Snapshots are set at order time and NEVER recomputed.
type OrderItem struct {
	ID         int64 `json:"id"`
	OrderID    int64 `json:"order_id"`
	VariantID  int64 `json:"variant_id"`
	SellerID   int64 `json:"seller_id"`
	CategoryID int64 `json:"category_id"`
	Qty        int   `json:"qty"`
	// UnitPriceMinor is the CHARGED unit price — already basket-discounted (CT-09).
	// Every downstream consumer (cashback, orderledger, sellerpayout, returns,
	// seller breakdown) derives from it, so the discount propagates via the snapshot.
	UnitPriceMinor int64 `json:"unit_price_minor"`
	// ListUnitPriceMinor is the pre-discount unit (= variant.price_minor); used for
	// the strikethrough + the per-line discount delta. Equals UnitPriceMinor when
	// BasketDiscountPct == 0.
	ListUnitPriceMinor int64 `json:"list_unit_price_minor"`
	// BasketDiscountPct is the snapshotted whole-percent basket discount applied to
	// this line (0 = none). Frozen at order time like CommissionPctBps.
	BasketDiscountPct     int    `json:"basket_discount_pct"`
	UnitPriceCurrency     string `json:"unit_price_currency"`
	CommissionPctBps      int    `json:"commission_pct_bps"`
	KdvPctBps             int    `json:"kdv_pct_bps"`
	CommissionAmountMinor int64  `json:"commission_amount_minor"`
	KdvAmountMinor        int64  `json:"kdv_amount_minor"`
	SellerNetMinor        int64  `json:"seller_net_minor"`
}

// CheckoutRequest is the input for Service.Checkout (legacy single-order flow).
type CheckoutRequest struct {
	UserID         int64
	ReservationID  string // from cart.Reserve; empty tolerated on idempotent retries
	Market         string // overrides service default when non-empty
	Currency       string // overrides first-item currency when non-empty
	CouponCode     string // optional coupon code (CT-03); empty = none
	IdempotencyKey string
}

// ── checkout-session types ────────────────────────────────────────────────────

// CheckoutSessionStatus is the lifecycle state of a multi-seller checkout session.
type CheckoutSessionStatus string

const (
	CheckoutSessionPending      CheckoutSessionStatus = "pending"
	CheckoutSessionPSPInitiated CheckoutSessionStatus = "psp_initiated"
	CheckoutSessionCompleted    CheckoutSessionStatus = "completed"
	CheckoutSessionFailed       CheckoutSessionStatus = "failed"
	CheckoutSessionExpired      CheckoutSessionStatus = "expired"
)

// CheckoutSession tracks a single PSP payment that covers N per-seller orders.
// id == PSP invoice_id so the webhook can resolve all order IDs on capture.
type CheckoutSession struct {
	ID            string                `json:"id"`
	UserID        int64                 `json:"user_id"`
	ReservationID string                `json:"reservation_id"`
	Status        CheckoutSessionStatus `json:"status"`
	OrderIDs      []int64               `json:"order_ids"`
	AmountMinor   int64                 `json:"amount_minor"`
	Currency      string                `json:"currency"`
	ProviderRef   string                `json:"provider_ref,omitempty"`
	ExpiresAt     time.Time             `json:"expires_at"`
	CreatedAt     time.Time             `json:"created_at"`
	UpdatedAt     time.Time             `json:"updated_at"`
}

// InitiateCheckoutRequest is the input for Service.InitiateCheckout.
type InitiateCheckoutRequest struct {
	UserID        int64
	ReservationID string // from cart.Reserve
	Market        string
	Currency      string
	SessionID     string // from Idempotency-Key header; becomes checkout_session.id and PSP invoice_id
	CouponCode    string // optional coupon code (CHK-04); empty = none
	BuyerName     string
	BuyerSurname  string
	BuyerEmail    string
	ReturnURL     string // 3DS redirect URL on success; falls back to PSP config default when empty
}

// InitiateCheckoutResponse is returned by Service.InitiateCheckout.
type InitiateCheckoutResponse struct {
	SessionID   string  // checkout_session.id
	ThreeDSHTML string  // rendered by mobile WebView
	ThreeDSURL  string  // full redirect URL for web clients (extracted from ThreeDSHTML form action)
	Orders      []Order // per-seller orders created
}
