package cashback

import (
	"errors"
	"fmt"
)

// CashbackK is the v8 accelerator constant (basis points × months).
// T_months = K / commission_bps; M_coin = (price × commission_bps) / K.
// Changing this value changes the cashback schedule for ALL new plans — requires a ledger migration.
const CashbackK int64 = 156000

// PlanTerms holds the frozen schedule computed once at plan creation.
type PlanTerms struct {
	TotalMonths            int
	MonthlyAmountMinor     int64 // paid in installments 1 .. TotalMonths-1
	MonthlyAmountLastMinor int64 // balloon payment in installment TotalMonths; always >= MonthlyAmountMinor
}

// ErrInvalidPlanInput is returned by ComputePlanTerms when inputs violate constraints.
var ErrInvalidPlanInput = errors.New("cashback: invalid plan input")

// ComputePlanTerms computes the immutable payment schedule for a new cashback plan.
//
// Math (all integer, no float64):
//
//	T = CashbackK / commissionBps          (integer division, truncated)
//	M = (priceMinor * commissionBps) / K   (integer division, truncated)
//	M_last = priceMinor - (T-1)*M          (balloon; guarantees exact principal coverage)
//
// Invariant: (T-1)*M + M_last == priceMinor (exact, not approximate).
//
// Overflow ceiling: priceMinor <= 1e14 (100 trillion kuruş ≈ 1 trillion TL) prevents
// overflow in (priceMinor * commissionBps) with commissionBps up to 10000.
func ComputePlanTerms(priceMinor int64, commissionBps int) (PlanTerms, error) {
	if priceMinor <= 0 || priceMinor > 1e14 {
		return PlanTerms{}, fmt.Errorf("%w: priceMinor %d out of range (0, 1e14]", ErrInvalidPlanInput, priceMinor)
	}
	if commissionBps < 100 || commissionBps > 10000 {
		return PlanTerms{}, fmt.Errorf("%w: commissionBps %d out of range [100, 10000]", ErrInvalidPlanInput, commissionBps)
	}
	totalMonths := int(CashbackK / int64(commissionBps))
	monthly := (priceMinor * int64(commissionBps)) / CashbackK
	if totalMonths < 1 || monthly < 1 {
		return PlanTerms{}, fmt.Errorf("%w: degenerate schedule (T=%d, M=%d)", ErrInvalidPlanInput, totalMonths, monthly)
	}
	lastMonth := priceMinor - int64(totalMonths-1)*monthly
	if lastMonth < monthly {
		// This indicates a programming error in the formula; should never occur for valid inputs.
		return PlanTerms{}, fmt.Errorf("%w: balloon %d < regular %d (programming error)", ErrInvalidPlanInput, lastMonth, monthly)
	}
	return PlanTerms{
		TotalMonths:            totalMonths,
		MonthlyAmountMinor:     monthly,
		MonthlyAmountLastMinor: lastMonth,
	}, nil
}

// InstallmentAmount returns the payout amount for the Nth installment (1-indexed).
// Returns 0 for out-of-range n.
func InstallmentAmount(terms PlanTerms, n int) int64 {
	if n < 1 || n > terms.TotalMonths {
		return 0
	}
	if n == terms.TotalMonths {
		return terms.MonthlyAmountLastMinor
	}
	return terms.MonthlyAmountMinor
}
