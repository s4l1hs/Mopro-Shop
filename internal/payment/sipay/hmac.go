package sipay

import (
	"crypto/sha512"
	"encoding/base64"
)

// ComputeHashKey produces the Sipay webhook hash_key for signature verification.
//
// Algorithm: base64( SHA512( merchantKey + statusCode + invoiceID + totalAmount + currencyCode ) )
//
// This is raw SHA-512 string concatenation — NOT an HMAC (no separate signing key).
// Sipay uses this scheme for both outbound webhook signatures and inbound refund verification.
//
// Field order is fixed by Sipay's API contract:
//
//	merchant_key → status_code → invoice_id → total_amount → currency_code
func ComputeHashKey(merchantKey, statusCode, invoiceID, totalAmount, currencyCode string) string {
	raw := merchantKey + statusCode + invoiceID + totalAmount + currencyCode
	sum := sha512.Sum512([]byte(raw))
	return base64.StdEncoding.EncodeToString(sum[:])
}
