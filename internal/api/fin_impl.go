package api

import (
	"context"

	"github.com/mopro/platform/internal/api/gen/fin"
)

// FinServer implements genfin.StrictServerInterface.
// All methods return 501 Not Implemented in Phase 4.0.
// Live handler migration happens in Phase 4.4+.
type FinServer struct{}

// ── Cashback ───────────────────────────────────────────────────────────────────

func (s *FinServer) ListCashbackPlans(_ context.Context, _ genfin.ListCashbackPlansRequestObject) (genfin.ListCashbackPlansResponseObject, error) {
	return notImplemented501[genfin.ListCashbackPlansResponseObject]()
}

func (s *FinServer) GetCashbackPlan(_ context.Context, _ genfin.GetCashbackPlanRequestObject) (genfin.GetCashbackPlanResponseObject, error) {
	return notImplemented501[genfin.GetCashbackPlanResponseObject]()
}

func (s *FinServer) ListCashbackPayments(_ context.Context, _ genfin.ListCashbackPaymentsRequestObject) (genfin.ListCashbackPaymentsResponseObject, error) {
	return notImplemented501[genfin.ListCashbackPaymentsResponseObject]()
}

// ── Wallet ─────────────────────────────────────────────────────────────────────

func (s *FinServer) GetWalletBalance(_ context.Context, _ genfin.GetWalletBalanceRequestObject) (genfin.GetWalletBalanceResponseObject, error) {
	return notImplemented501[genfin.GetWalletBalanceResponseObject]()
}

func (s *FinServer) ListWalletTransactions(_ context.Context, _ genfin.ListWalletTransactionsRequestObject) (genfin.ListWalletTransactionsResponseObject, error) {
	return notImplemented501[genfin.ListWalletTransactionsResponseObject]()
}

// compile-time interface check
var _ genfin.StrictServerInterface = (*FinServer)(nil)
