package orderledger

import "errors"

// ErrInvalidCaptureInput is returned by Compute when the inputs are outside
// physically valid ranges (e.g. gross < 1 TL, which would produce truncation
// artifacts that break the ledger's AmountMinor > 0 invariant).
var ErrInvalidCaptureInput = errors.New("orderledger: invalid capture input")

// Compute derives the balanced 2-to-5-line ledger entries for a PSP capture.
//
// commission_revenue absorbs the integer truncation residual so sum(C) == GrossMinor:
//
//	commission_revenue = GrossMinor - SellerNetMinor - KdvMinor - ShippingMinor
//
// Any line whose AmountMinor resolves to zero is excluded — this applies to
// commission_revenue (if all commission was truncated), kdv_payable (if no KDV),
// and shipping_payable (if no shipping). DR psp_receivable and CR seller_payable
// are always positive by input validation.
//
// Invariants: sum(D) == sum(C) == GrossMinor; every line AmountMinor > 0.
// Returns ErrInvalidCaptureInput if GrossMinor < 100 (< 1 TL).
//
// This function is pure: no I/O, no side effects, deterministic.
func Compute(in CaptureInputs) (CaptureEntries, error) {
	if in.GrossMinor < 100 {
		return CaptureEntries{}, ErrInvalidCaptureInput
	}

	commissionRevenue := in.GrossMinor - in.SellerNetMinor - in.KdvMinor - in.ShippingMinor

	candidates := []LedgerLine{
		{AccountType: "asset:psp_receivable", Direction: "D", AmountMinor: in.GrossMinor},
		{AccountType: "liability:seller_payable", SellerID: in.SellerID, Direction: "C", AmountMinor: in.SellerNetMinor},
		{AccountType: "equity:retained_commission", Direction: "C", AmountMinor: commissionRevenue},
		{AccountType: "liability:kdv_payable", Direction: "C", AmountMinor: in.KdvMinor},
		{AccountType: "liability:shipping_payable", Direction: "C", AmountMinor: in.ShippingMinor},
	}
	lines := make([]LedgerLine, 0, len(candidates))
	for _, l := range candidates {
		if l.AmountMinor > 0 {
			lines = append(lines, l)
		}
	}
	return CaptureEntries{Lines: lines}, nil
}

// Aggregate sums item-level frozen snapshots into CaptureInputs for Compute.
// GrossMinor comes from the order aggregate (order.total_minor), not recomputed
// from items, so it reflects the exact PSP capture amount.
func Aggregate(ev OrderPaidEvent) CaptureInputs {
	var sellerNet, commission, kdv int64
	for _, it := range ev.Items {
		sellerNet += it.SellerNetMinor
		commission += it.CommissionAmountMinor
		kdv += it.KdvAmountMinor
	}
	return CaptureInputs{
		OrderID:         ev.OrderID,
		SellerID:        ev.SellerID,
		GrossMinor:      ev.GrossMinor,
		SellerNetMinor:  sellerNet,
		CommissionMinor: commission,
		KdvMinor:        kdv,
		ShippingMinor:   ev.ShippingMinor,
		Currency:        ev.Currency,
		Market:          ev.Market,
	}
}
