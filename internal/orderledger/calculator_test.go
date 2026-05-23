package orderledger

import (
	"testing"
)

// helper to sum amounts for a given direction in CaptureEntries.
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
	got := Compute(in)
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
	got := Compute(in)
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
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
	got := Compute(in)
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

func TestCompute_CommissionAbsorbsTruncation(t *testing.T) {
	// Items compute: gross=10001, seller_net=7999, kdv=400, shipping=0.
	// By formula: commission_revenue = 10001 - 7999 - 400 - 0 = 1602
	in := CaptureInputs{
		OrderID:         4,
		SellerID:        40,
		GrossMinor:      10001,
		SellerNetMinor:  7999,
		CommissionMinor: 1601, // pre-computed audit value (may differ by 1)
		KdvMinor:        400,
		ShippingMinor:   0,
		Currency:        "TRY",
	}
	got := Compute(in)
	if sumDir(got, "D") != sumDir(got, "C") {
		t.Fatalf("unbalanced: D=%d C=%d", sumDir(got, "D"), sumDir(got, "C"))
	}
	// commission_revenue (by formula) should absorb the +1
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
	got := Compute(in)
	for _, l := range got.Lines {
		if l.AccountType == "liability:seller_payable" {
			if l.SellerID != in.SellerID {
				t.Fatalf("seller_payable SellerID=%d, want %d", l.SellerID, in.SellerID)
			}
		}
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
