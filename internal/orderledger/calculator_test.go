package orderledger

import (
	"errors"
	"testing"
)

// sumDir sums AmountMinor for all lines with the given direction.
func sumDir(c CaptureEntries, dir string) int64 {
	var total int64
	for _, l := range c.Lines {
		if l.Direction == dir {
			total += l.AmountMinor
		}
	}
	return total
}

func TestCompute_Balanced_WithShipping(t *testing.T) {
	in := CaptureInputs{
		OrderID:         1,
		SellerID:        10,
		GrossMinor:      12000,
		SellerNetMinor:  9600,
		CommissionMinor: 2000,
		KdvMinor:        400,
		ShippingMinor:   0,
		Currency:        "TRY",
	}
	got, err := Compute(in)
	if err != nil {
		t.Fatalf("Compute returned error: %v", err)
	}
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
	if sumDir(got, "D") != in.GrossMinor {
		t.Fatalf("debit total %d != gross %d", sumDir(got, "D"), in.GrossMinor)
	}
}

func TestCompute_Balanced_NoShipping(t *testing.T) {
	in := CaptureInputs{
		OrderID:         2,
		SellerID:        20,
		GrossMinor:      10000,
		SellerNetMinor:  8000,
		CommissionMinor: 1667,
		KdvMinor:        333,
		ShippingMinor:   0,
		Currency:        "TRY",
	}
	got, err := Compute(in)
	if err != nil {
		t.Fatalf("Compute returned error: %v", err)
	}
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
	// DR psp + CR seller + CR commission + CR kdv = 4 lines (no shipping, no zero lines)
	if len(got.Lines) != 4 {
		t.Fatalf("expected 4 lines when shipping=0, got %d", len(got.Lines))
	}
}

func TestCompute_ShippingLine_PresentWhenNonZero(t *testing.T) {
	in := CaptureInputs{
		OrderID:         3,
		SellerID:        30,
		GrossMinor:      11500,
		SellerNetMinor:  9000,
		CommissionMinor: 1250,
		KdvMinor:        250,
		ShippingMinor:   1000,
		Currency:        "TRY",
	}
	got, err := Compute(in)
	if err != nil {
		t.Fatalf("Compute returned error: %v", err)
	}
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
	if len(got.Lines) != 5 {
		t.Fatalf("expected 5 lines when shipping>0, got %d", len(got.Lines))
	}
	var hasShipping bool
	for _, l := range got.Lines {
		if l.AccountType == "liability:shipping_payable" {
			hasShipping = true
			if l.AmountMinor != in.ShippingMinor {
				t.Fatalf("shipping line amount %d != %d", l.AmountMinor, in.ShippingMinor)
			}
		}
	}
	if !hasShipping {
		t.Fatal("expected shipping_payable line")
	}
}

func TestCompute_ZeroKdv_ExcludesKdvLine(t *testing.T) {
	// When kdv is 0, the kdv_payable line must be excluded.
	in := CaptureInputs{
		OrderID:         6,
		SellerID:        60,
		GrossMinor:      10000,
		SellerNetMinor:  8333,
		CommissionMinor: 1667,
		KdvMinor:        0,
		ShippingMinor:   0,
		Currency:        "TRY",
	}
	got, err := Compute(in)
	if err != nil {
		t.Fatalf("Compute returned error: %v", err)
	}
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
	for _, l := range got.Lines {
		if l.AmountMinor <= 0 {
			t.Fatalf("zero-amount line emitted: %+v", l)
		}
		if l.AccountType == "liability:kdv_payable" {
			t.Fatal("kdv_payable line must not be emitted when kdv=0")
		}
	}
	// DR psp + CR seller + CR commission = 3 lines
	if len(got.Lines) != 3 {
		t.Fatalf("expected 3 lines when kdv=0 and shipping=0, got %d", len(got.Lines))
	}
}

func TestCompute_CommissionAbsorbsTruncation(t *testing.T) {
	// gross=10001, sellerNet=7999, kdv=400, shipping=0 →
	// commissionRevenue = 10001 - 7999 - 400 = 1602 (absorbs the +1 residual)
	in := CaptureInputs{
		OrderID:         4,
		SellerID:        40,
		GrossMinor:      10001,
		SellerNetMinor:  7999,
		CommissionMinor: 1601, // pre-computed audit value (differs by 1)
		KdvMinor:        400,
		ShippingMinor:   0,
		Currency:        "TRY",
	}
	got, err := Compute(in)
	if err != nil {
		t.Fatalf("Compute returned error: %v", err)
	}
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
	for _, l := range got.Lines {
		if l.AccountType == "equity:retained_commission" {
			if l.AmountMinor != 1602 {
				t.Fatalf("commission_revenue=%d, want 1602", l.AmountMinor)
			}
		}
	}
}

func TestCompute_SellerPayableHasSellerID(t *testing.T) {
	in := CaptureInputs{
		OrderID:         5,
		SellerID:        99,
		GrossMinor:      5000,
		SellerNetMinor:  4000,
		CommissionMinor: 833,
		KdvMinor:        167,
		ShippingMinor:   0,
		Currency:        "TRY",
	}
	got, err := Compute(in)
	if err != nil {
		t.Fatalf("Compute returned error: %v", err)
	}
	for _, l := range got.Lines {
		if l.AccountType == "liability:seller_payable" {
			if l.SellerID != in.SellerID {
				t.Fatalf("seller_payable SellerID=%d, want %d", l.SellerID, in.SellerID)
			}
		}
	}
}

func TestCompute_BelowMinGross_ReturnsError(t *testing.T) {
	for _, gross := range []int64{0, 1, 50, 99} {
		in := CaptureInputs{
			OrderID:        7,
			SellerID:       1,
			GrossMinor:     gross,
			SellerNetMinor: gross,
			Currency:       "TRY",
		}
		_, err := Compute(in)
		if !errors.Is(err, ErrInvalidCaptureInput) {
			t.Fatalf("gross=%d: expected ErrInvalidCaptureInput, got %v", gross, err)
		}
	}
}

func TestCompute_AtMinGross_NoError(t *testing.T) {
	in := CaptureInputs{
		OrderID:         8,
		SellerID:        1,
		GrossMinor:      100,
		SellerNetMinor:  80,
		CommissionMinor: 16,
		KdvMinor:        4,
		ShippingMinor:   0,
		Currency:        "TRY",
	}
	got, err := Compute(in)
	if err != nil {
		t.Fatalf("gross=100 should be valid, got error: %v", err)
	}
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced at min gross: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
}

func TestAggregate_SumsItems(t *testing.T) {
	ev := OrderPaidEvent{
		OrderID:       10,
		SellerID:      5,
		GrossMinor:    20000,
		ShippingMinor: 500,
		Currency:      "TRY",
		Market:        "TR",
		Items: []PaidItem{
			{CommissionAmountMinor: 1000, KdvAmountMinor: 200, SellerNetMinor: 8800},
			{CommissionAmountMinor: 900, KdvAmountMinor: 180, SellerNetMinor: 7920},
		},
	}
	got := Aggregate(ev)
	if got.CommissionMinor != 1900 {
		t.Fatalf("commission=%d, want 1900", got.CommissionMinor)
	}
	if got.KdvMinor != 380 {
		t.Fatalf("kdv=%d, want 380", got.KdvMinor)
	}
	if got.SellerNetMinor != 16720 {
		t.Fatalf("seller_net=%d, want 16720", got.SellerNetMinor)
	}
	if got.GrossMinor != ev.GrossMinor {
		t.Fatalf("gross=%d, want %d", got.GrossMinor, ev.GrossMinor)
	}
	if got.ShippingMinor != ev.ShippingMinor {
		t.Fatalf("shipping=%d, want %d", got.ShippingMinor, ev.ShippingMinor)
	}
}
