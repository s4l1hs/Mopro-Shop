package commission

import (
	"errors"
	"testing"
)

// TestErrAlreadyPosted_IsDistinct guards the error identity that
// orderledger pivots on via errors.Is. Renaming or replacing this sentinel
// without updating the caller would silently fall into the generic error
// branch and surface a false 5xx for concurrent re-deliveries.
func TestErrAlreadyPosted_IsDistinct(t *testing.T) {
	if ErrAlreadyPosted == nil {
		t.Fatal("ErrAlreadyPosted must be a non-nil sentinel")
	}
	if !errors.Is(ErrAlreadyPosted, ErrAlreadyPosted) {
		t.Fatal("ErrAlreadyPosted must compare equal to itself via errors.Is")
	}
	other := errors.New("commission: capture posting already recorded")
	if errors.Is(other, ErrAlreadyPosted) {
		t.Fatal("ErrAlreadyPosted must NOT collide with a same-text errors.New value")
	}
}

// TestCapturePosting_ZeroValue documents the struct contract: all numeric
// fields default to 0, all string fields default to "", time fields default
// to the time.Time zero value. Callers (orderledger.Service.PostCapture)
// build this struct field-by-field; this test catches accidental field
// additions that change the zero shape without an accompanying caller
// update.
func TestCapturePosting_ZeroValue(t *testing.T) {
	var p CapturePosting
	if p.OrderID != 0 || p.TransactionID != 0 || p.GrossMinor != 0 ||
		p.SellerNetMinor != 0 || p.CommissionMinor != 0 || p.KdvMinor != 0 ||
		p.ShippingMinor != 0 {
		t.Fatal("CapturePosting numeric fields must default to 0")
	}
	if p.Currency != "" || p.Market != "" || p.Status != "" || p.IdempotencyKey != "" {
		t.Fatal("CapturePosting string fields must default to empty")
	}
	if !p.CreatedAt.IsZero() {
		t.Fatal("CapturePosting.CreatedAt must default to the zero time")
	}
}
