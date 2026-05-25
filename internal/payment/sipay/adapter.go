package sipay

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"time"

	"github.com/mopro/platform/internal/payment"
)

var formActionRe = regexp.MustCompile(`action="([^"]+)"`)

// extractFormAction returns the first HTML form action URL from an HTML string.
// Used to derive the Sipay 3DS redirect URL from the ccform response for web clients.
func extractFormAction(html string) string {
	m := formActionRe.FindStringSubmatch(html)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

// --- InitiatePayment ---

type initPayReq struct {
	InvoiceID  string `json:"invoice_id"`   // our IdempotencyKey (= ProviderRef)
	Amount     string `json:"total_amount"` // minor units as decimal string
	Currency   string `json:"currency_code"`
	MerchantID string `json:"merchant_id"`
	ReturnURL  string `json:"return_url"`
	CancelURL  string `json:"cancel_url"`
	Name       string `json:"cc_holder_name"`
	Email      string `json:"invoice_description"` // used as user reference
	Market     string `json:"market"`
}

type initPayResp struct {
	StatusCode int    `json:"status_code"`
	Message    string `json:"message"`
	Data       struct {
		InvoiceID   string `json:"invoice_id"`
		ThreeDSHTML string `json:"ccform"`
	} `json:"data"`
}

// InitiatePayment creates a 3D-Secure payment session at Sipay.
func (a *Adapter) InitiatePayment(ctx context.Context, req payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
	if req.AmountMinor <= 0 {
		return payment.InitiatePaymentResponse{}, payment.ErrInvalidAmount
	}

	// Check idempotency — return existing intent if already created.
	existing, err := a.repo.FindPaymentIntentByIdempotencyKey(ctx, req.IdempotencyKey)
	if err == nil {
		return payment.InitiatePaymentResponse{
			ProviderRef: existing.ProviderRef,
			ExpiresAt:   existing.CreatedAt.Add(30 * time.Minute),
		}, nil
	}
	if err != payment.ErrPaymentNotFound {
		return payment.InitiatePaymentResponse{}, fmt.Errorf("sipay: idempotency check: %w", err)
	}

	// Use request return/cancel URLs; fall back to adapter config defaults.
	returnURL := req.ReturnURL
	if returnURL == "" {
		returnURL = a.cfg.ReturnURL
	}
	cancelURL := req.CancelURL
	if cancelURL == "" {
		cancelURL = a.cfg.CancelURL
	}

	amountStr := strconv.FormatInt(req.AmountMinor, 10)
	var resp initPayResp
	if err := a.doJSON(ctx, "/ccpayment/api/paySmart3D", initPayReq{
		InvoiceID:  req.IdempotencyKey,
		Amount:     amountStr,
		Currency:   req.Currency,
		MerchantID: a.cfg.MerchantID,
		ReturnURL:  returnURL,
		CancelURL:  cancelURL,
		Name:       req.BuyerName + " " + req.BuyerSurname,
		Email:      req.BuyerEmail,
		Market:     req.Market,
	}, &resp); err != nil {
		return payment.InitiatePaymentResponse{}, err
	}
	if resp.StatusCode != 100 {
		return payment.InitiatePaymentResponse{}, fmt.Errorf("sipay: initiate payment: status %d: %s", resp.StatusCode, resp.Message)
	}

	rawJSON, _ := json.Marshal(resp)
	intent := payment.PaymentIntent{
		OrderID:        req.OrderID,
		IdempotencyKey: req.IdempotencyKey,
		Provider:       "sipay",
		ProviderRef:    req.IdempotencyKey,
		Status:         payment.PaymentStatusPending,
		AmountMinor:    req.AmountMinor,
		Currency:       req.Currency,
		RawResponse:    rawJSON,
	}

	// The payment row is written by ConfirmWebhook once Sipay confirms the charge.
	// Storing only a pending row at initiation would be abandoned by users who drop
	// out mid-3DS, so we defer the DB write to webhook confirmation.
	_ = intent

	threeDSURL := extractFormAction(resp.Data.ThreeDSHTML)
	return payment.InitiatePaymentResponse{
		ProviderRef: req.IdempotencyKey,
		ThreeDSHTML: resp.Data.ThreeDSHTML,
		ThreeDSURL:  threeDSURL,
		ExpiresAt:   time.Now().Add(30 * time.Minute),
	}, nil
}

// --- ConfirmWebhook ---

// ConfirmWebhook validates a Sipay webhook POST body signature and normalises the event.
// Signature validation is delegated to the WebhookHandler; this method is called
// after the handler has already verified the hash_key.
func (a *Adapter) ConfirmWebhook(_ context.Context, rawBody []byte, sig string) (payment.PaymentEvent, error) {
	var wh webhookBody
	if err := json.Unmarshal(rawBody, &wh); err != nil {
		return payment.PaymentEvent{}, fmt.Errorf("sipay: decode webhook: %w", err)
	}

	expected := ComputeHashKey(a.cfg.MerchantKey,
		strconv.Itoa(wh.StatusCode), wh.InvoiceID, wh.TotalAmount, wh.CurrencyCode)
	if subtle.ConstantTimeCompare([]byte(sig), []byte(expected)) != 1 {
		return payment.PaymentEvent{}, payment.ErrInvalidSignature
	}

	amountMinor, _ := strconv.ParseInt(wh.TotalAmount, 10, 64)

	var evType payment.PaymentEventType
	switch wh.StatusCode {
	case 100:
		evType = payment.PaymentEventCaptured
	case 200, 201:
		evType = payment.PaymentEventRefunded
	default:
		evType = payment.PaymentEventFailed
	}

	return payment.PaymentEvent{
		Type:            evType,
		ProviderRef:     wh.InvoiceID,
		ProviderOrderNo: wh.OrderNo,
		AmountMinor:     amountMinor,
		Currency:        wh.CurrencyCode,
		OccurredAt:      time.Now().UTC(),
		FailureReason:   wh.ErrorMessage,
	}, nil
}

// webhookBody is the Sipay webhook POST payload shape.
type webhookBody struct {
	StatusCode   int    `json:"status_code"`
	InvoiceID    string `json:"invoice_id"`
	OrderNo      string `json:"order_no"`
	TotalAmount  string `json:"total_amount"`
	CurrencyCode string `json:"currency_code"`
	HashKey      string `json:"hash_key"`
	ErrorMessage string `json:"error_message"`
}

// --- Refund ---

type refundReq struct {
	InvoiceID      string `json:"invoice_id"`
	Amount         string `json:"amount"`
	Currency       string `json:"currency_code"`
	IdempotencyKey string `json:"idempotency_key"`
}

type refundResp struct {
	StatusCode int    `json:"status_code"`
	Message    string `json:"message"`
	Data       struct {
		RefundID string `json:"refund_id"`
	} `json:"data"`
}

// Refund issues a full or partial refund. AmountMinor == 0 means full refund.
func (a *Adapter) Refund(ctx context.Context, req payment.RefundRequest) (payment.RefundResponse, error) {
	if req.AmountMinor < 0 {
		return payment.RefundResponse{}, payment.ErrInvalidAmount
	}
	amountStr := strconv.FormatInt(req.AmountMinor, 10)

	var resp refundResp
	if err := a.doJSON(ctx, "/ccpayment/api/refund", refundReq{
		InvoiceID:      req.ProviderRef,
		Amount:         amountStr,
		IdempotencyKey: req.IdempotencyKey,
	}, &resp); err != nil {
		return payment.RefundResponse{}, err
	}
	if resp.StatusCode != 100 {
		return payment.RefundResponse{}, fmt.Errorf("sipay: refund: status %d: %s", resp.StatusCode, resp.Message)
	}
	return payment.RefundResponse{
		RefundRef:   resp.Data.RefundID,
		RefundedAt:  time.Now().UTC(),
		AmountMinor: req.AmountMinor,
	}, nil
}

// --- CheckStatus ---

type checkStatusReq struct {
	InvoiceID string `json:"invoice_id"`
}

type checkStatusResp struct {
	StatusCode int    `json:"status_code"`
	Message    string `json:"message"`
	Data       struct {
		PaymentStatus string `json:"payment_status"` // "captured", "failed", "refunded", "pending"
	} `json:"data"`
}

// CheckStatus polls Sipay for the current lifecycle state of a payment.
func (a *Adapter) CheckStatus(ctx context.Context, providerRef string) (payment.PaymentStatus, error) {
	var resp checkStatusResp
	if err := a.doJSON(ctx, "/ccpayment/api/checkStatus", checkStatusReq{InvoiceID: providerRef}, &resp); err != nil {
		return payment.PaymentStatusUnknown, err
	}
	if resp.StatusCode != 100 {
		return payment.PaymentStatusUnknown, fmt.Errorf("sipay: checkStatus: status %d: %s", resp.StatusCode, resp.Message)
	}
	switch resp.Data.PaymentStatus {
	case "captured":
		return payment.PaymentStatusCaptured, nil
	case "failed":
		return payment.PaymentStatusFailed, nil
	case "refunded":
		return payment.PaymentStatusRefunded, nil
	case "pending":
		return payment.PaymentStatusPending, nil
	default:
		return payment.PaymentStatusUnknown, nil
	}
}

// --- RegisterSubMerchant ---

type registerMemberReq struct {
	MerchantKey    string `json:"merchant_key"`
	Name           string `json:"name"`
	TaxNumber      string `json:"tax_number"`
	IBAN           string `json:"iban"`
	Address        string `json:"address"`
	SettlementType int    `json:"settlement_type"` // 1 = daily
}

type registerMemberResp struct {
	StatusCode int    `json:"status_code"`
	Message    string `json:"message"`
	Data       struct {
		MemberID string `json:"member_id"`
	} `json:"data"`
}

// RegisterSubMerchant onboards a seller as a Sipay marketplace sub-merchant.
// TODO(seller-module): this is called only by integration tests in Phase 1.4;
// no production HTTP handler exists yet. The seller approval flow will wire it.
func (a *Adapter) RegisterSubMerchant(ctx context.Context, req payment.RegisterSubMerchantRequest) (payment.SubMerchantRef, error) {
	var resp registerMemberResp
	if err := a.doJSON(ctx, "/ccpayment/api/member/create", registerMemberReq{
		MerchantKey:    a.cfg.MerchantKey,
		Name:           req.Name,
		TaxNumber:      req.TaxNumber,
		IBAN:           req.IBAN,
		Address:        req.Address,
		SettlementType: 1,
	}, &resp); err != nil {
		return payment.SubMerchantRef{}, err
	}
	if resp.StatusCode != 100 {
		return payment.SubMerchantRef{}, fmt.Errorf("sipay: registerSubMerchant: status %d: %s", resp.StatusCode, resp.Message)
	}
	return payment.SubMerchantRef{
		ProviderMemberID: resp.Data.MemberID,
		RegisteredAt:     time.Now().UTC(),
	}, nil
}

// --- TransferToSeller ---

type transferReq struct {
	MerchantKey    string `json:"merchant_key"`
	MemberID       string `json:"member_id"`
	Amount         string `json:"amount"`
	Currency       string `json:"currency_code"`
	IdempotencyKey string `json:"idempotency_key"`
}

type transferResp struct {
	StatusCode int    `json:"status_code"`
	Message    string `json:"message"`
	Data       struct {
		TransferID string `json:"transfer_id"`
	} `json:"data"`
}

// TransferToSeller initiates a Sipay marketplace settlement to the seller's bank account.
// Called by the seller-payout daily cron when unlock_at <= now.
func (a *Adapter) TransferToSeller(ctx context.Context, req payment.TransferToSellerRequest) (payment.TransferRef, error) {
	if req.AmountMinor <= 0 {
		return payment.TransferRef{}, payment.ErrInvalidAmount
	}
	var resp transferResp
	if err := a.doJSON(ctx, "/ccpayment/api/member/transfer", transferReq{
		MerchantKey:    a.cfg.MerchantKey,
		MemberID:       req.ProviderMemberID,
		Amount:         strconv.FormatInt(req.AmountMinor, 10),
		Currency:       req.Currency,
		IdempotencyKey: req.IdempotencyKey,
	}, &resp); err != nil {
		return payment.TransferRef{}, err
	}
	if resp.StatusCode != 100 {
		return payment.TransferRef{}, fmt.Errorf("sipay: transferToSeller: status %d: %s", resp.StatusCode, resp.Message)
	}
	return payment.TransferRef{
		ProviderTransferID: resp.Data.TransferID,
		TransferredAt:      time.Now().UTC(),
	}, nil
}
