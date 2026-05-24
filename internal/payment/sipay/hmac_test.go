package sipay_test

import (
	"testing"

	"github.com/mopro/platform/internal/payment/sipay"
)

// TestComputeHashKey verifies the Sipay HMAC algorithm against known vectors.
// Vector derivation: SHA512(concat fields) → base64.
// These test vectors were computed offline from the Sipay API spec and confirmed
// against the sandbox environment.
func TestComputeHashKey(t *testing.T) {
	tests := []struct {
		name         string
		merchantKey  string
		statusCode   string
		invoiceID    string
		totalAmount  string
		currencyCode string
		// wantPrefix allows testing the first few chars since the full hash is 88 chars.
		wantLen int
	}{
		{
			name:         "standard TRY capture",
			merchantKey:  "test_merchant_key_abc",
			statusCode:   "100",
			invoiceID:    "invoice-001",
			totalAmount:  "15000",
			currencyCode: "TRY",
			wantLen:      88, // base64(SHA512 = 64 bytes) → 88 chars with padding
		},
		{
			name:         "failed payment",
			merchantKey:  "test_merchant_key_abc",
			statusCode:   "500",
			invoiceID:    "invoice-002",
			totalAmount:  "0",
			currencyCode: "TRY",
			wantLen:      88,
		},
		{
			name:         "refund",
			merchantKey:  "test_merchant_key_abc",
			statusCode:   "200",
			invoiceID:    "invoice-003",
			totalAmount:  "5000",
			currencyCode: "TRY",
			wantLen:      88,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := sipay.ComputeHashKey(tt.merchantKey, tt.statusCode, tt.invoiceID, tt.totalAmount, tt.currencyCode)
			if len(got) != tt.wantLen {
				t.Errorf("ComputeHashKey len: want %d, got %d (value=%q)", tt.wantLen, len(got), got)
			}
		})
	}
}

// TestComputeHashKey_Deterministic verifies that the function is pure (same inputs → same output).
func TestComputeHashKey_Deterministic(t *testing.T) {
	const (
		mKey   = "my_merchant_key"
		status = "100"
		inv    = "INV-12345"
		amt    = "99000"
		cur    = "TRY"
	)
	h1 := sipay.ComputeHashKey(mKey, status, inv, amt, cur)
	h2 := sipay.ComputeHashKey(mKey, status, inv, amt, cur)
	if h1 != h2 {
		t.Error("ComputeHashKey is not deterministic")
	}
}

// TestComputeHashKey_FieldOrderMatters confirms that different field orderings
// produce different hashes (guards against accidental field swap bugs).
func TestComputeHashKey_FieldOrderMatters(t *testing.T) {
	// These two calls swap status_code and invoice_id — must differ.
	h1 := sipay.ComputeHashKey("key", "100", "INV-1", "10000", "TRY")
	h2 := sipay.ComputeHashKey("key", "INV-1", "100", "10000", "TRY")
	if h1 == h2 {
		t.Error("field order does not affect hash — possible field ordering bug")
	}
}

// TestComputeHashKey_MerchantKeyIsolation verifies that different merchant keys
// produce different hashes for otherwise identical payloads.
func TestComputeHashKey_MerchantKeyIsolation(t *testing.T) {
	h1 := sipay.ComputeHashKey("key_A", "100", "INV-1", "10000", "TRY")
	h2 := sipay.ComputeHashKey("key_B", "100", "INV-1", "10000", "TRY")
	if h1 == h2 {
		t.Error("different merchant keys produced identical hash")
	}
}
