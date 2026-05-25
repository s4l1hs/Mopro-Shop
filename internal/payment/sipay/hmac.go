package sipay

import (
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
)

// ComputeHashKey produces the Sipay webhook / refund hash_key for signature verification.
//
// Algorithm: base64( SHA-512( merchantKey + statusCode + invoiceID + totalAmount + currencyCode ) )
//
// This is raw SHA-512 string concatenation — NOT an HMAC (no separate signing key).
// Field order is fixed by Sipay's API contract:
//
//	merchant_key → status_code → invoice_id → total_amount → currency_code
func ComputeHashKey(merchantKey, statusCode, invoiceID, totalAmount, currencyCode string) string {
	raw := merchantKey + statusCode + invoiceID + totalAmount + currencyCode
	sum := sha512.Sum512([]byte(raw))
	return base64.StdEncoding.EncodeToString(sum[:])
}

// Payment3DSignFields contains the named fields needed to sign a payment3D request.
// Keeping them in a struct makes it impossible to accidentally swap positional args.
type Payment3DSignFields struct {
	Total        string // amount in minor units as a decimal string
	Installment  string // "1" for single payment; "3", "6", "9", "12" for instalments
	CurrencyCode string // e.g. "TRY"
	MerchantKey  string
	InvoiceID    string
	AppSecret    string
}

// SignPayment3D computes hash_key for a /ccpayment/api/paySmart3D request.
//
// Algorithm per Sipay docs (payment3D endpoint):
//
//	base64( SHA-256( total + installment + currency_code + merchant_key + invoice_id + app_secret ) )
//
// Note: payment3D uses SHA-256, while webhook/refund uses SHA-512 — different schemes.
func SignPayment3D(f Payment3DSignFields) string {
	raw := f.Total + f.Installment + f.CurrencyCode + f.MerchantKey + f.InvoiceID + f.AppSecret
	sum := sha256.Sum256([]byte(raw))
	return base64.StdEncoding.EncodeToString(sum[:])
}

// SignGetToken computes hash_key for the /ccpayment/api/token endpoint.
//
// Algorithm per Sipay docs:
//
//	base64( SHA-256( app_id + app_secret + merchant_id ) )
func SignGetToken(appID, appSecret, merchantID string) string {
	raw := appID + appSecret + merchantID
	sum := sha256.Sum256([]byte(raw))
	return base64.StdEncoding.EncodeToString(sum[:])
}

// SignWebhook verifies an inbound Sipay webhook by computing the expected hash_key.
// It is a named alias for ComputeHashKey — the webhook and refund confirmation
// endpoints share the same SHA-512 / base64 scheme.
//
// Use this in tests and signature-verification code to make the intent explicit.
func SignWebhook(merchantKey, statusCode, invoiceID, totalAmount, currencyCode string) string {
	return ComputeHashKey(merchantKey, statusCode, invoiceID, totalAmount, currencyCode)
}
