package orderledger

// Compute derives the balanced ledger lines for a PSP capture event.
//
// commission_revenue absorbs the integer truncation residual from the
// pre-computed item snapshots, guaranteeing sum(C) == GrossMinor exactly:
//
//	commission_revenue = GrossMinor - SellerNetMinor - KdvMinor - ShippingMinor
//
// Zero-amount lines (e.g. zero shipping) are excluded so the wallet service's
// AmountMinor > 0 invariant is never violated.
//
// This function is pure: no I/O, no side effects, deterministic.
func Compute(in CaptureInputs) CaptureEntries {
	commissionRevenue := in.GrossMinor - in.SellerNetMinor - in.KdvMinor - in.ShippingMinor

	lines := make([]LedgerLine, 0, 5)
	lines = append(lines,
		LedgerLine{AccountType: "asset:psp_receivable", Direction: "D", AmountMinor: in.GrossMinor},
		LedgerLine{AccountType: "liability:seller_payable", SellerID: in.SellerID, Direction: "C", AmountMinor: in.SellerNetMinor},
		LedgerLine{AccountType: "equity:retained_commission", Direction: "C", AmountMinor: commissionRevenue},
		LedgerLine{AccountType: "liability:kdv_payable", Direction: "C", AmountMinor: in.KdvMinor},
	)
	if in.ShippingMinor > 0 {
		lines = append(lines, LedgerLine{AccountType: "liability:shipping_payable", Direction: "C", AmountMinor: in.ShippingMinor})
	}
	return CaptureEntries{Lines: lines}
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
