package api

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"time"

	openapi_types "github.com/oapi-codegen/runtime/types"

	genfin "github.com/mopro/platform/internal/api/gen/fin"
	"github.com/mopro/platform/internal/cashback"
	identitymw "github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/wallet"
)

const (
	finDefaultLimit = 20
	finMaxLimit     = 100
)

// FinServer implements genfin.StrictServerInterface.
type FinServer struct {
	WalletSvc       wallet.Service
	CashbackRepo    cashback.Repository
	DefaultCurrency string
}

// ── cursor helpers ─────────────────────────────────────────────────────────────

type finCursor struct {
	LastID int64 `json:"last_id"`
}

func finEncodeCursor(lastID int64) string {
	b, _ := json.Marshal(finCursor{LastID: lastID})
	return base64.StdEncoding.EncodeToString(b)
}

func finDecodeCursor(s string) (int64, error) {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return 0, fmt.Errorf("fin: invalid cursor: %w", err)
	}
	var c finCursor
	if err := json.Unmarshal(b, &c); err != nil {
		return 0, fmt.Errorf("fin: invalid cursor json: %w", err)
	}
	return c.LastID, nil
}

func finResolveLimit(p *int) int {
	if p == nil || *p < 1 {
		return finDefaultLimit
	}
	if *p > finMaxLimit {
		return finMaxLimit
	}
	return *p
}

// ── Wallet ─────────────────────────────────────────────────────────────────────

// GetWalletBalance returns the coin wallet balance for the authenticated user.
// Balance is read from the wallet_schema.balances materialized view (stale ≤ refresh interval).
// last_updated_at reflects the server wall clock at request time, NOT the MV refresh timestamp.
func (s *FinServer) GetWalletBalance(ctx context.Context, req genfin.GetWalletBalanceRequestObject) (genfin.GetWalletBalanceResponseObject, error) {
	userID := identitymw.UserIDFromCtx(ctx)
	currency := s.DefaultCurrency
	if req.Params.Currency != nil && *req.Params.Currency != "" {
		currency = *req.Params.Currency
	}

	// Resolve account without side-effects; return 0 balance if wallet never created.
	acctID, _, err := s.WalletSvc.FindAccountByOwnerAnyStatus(ctx, "user", userID, currency)
	if err != nil {
		return nil, err
	}
	var balance int64
	if acctID > 0 {
		balance, err = s.WalletSvc.GetBalance(ctx, acctID)
		if err != nil {
			return nil, err
		}
	}
	return genfin.GetWalletBalance200JSONResponse{
		AmountMinor: balance,
		Currency:    currency,
		// MV last_updated_at is not directly accessible; server time is the safe fallback.
		LastUpdatedAt: time.Now().UTC(),
	}, nil
}

// ListWalletTransactions returns a cursor-paginated list of wallet ledger entries
// for the authenticated user's coin wallet.
func (s *FinServer) ListWalletTransactions(ctx context.Context, req genfin.ListWalletTransactionsRequestObject) (genfin.ListWalletTransactionsResponseObject, error) {
	userID := identitymw.UserIDFromCtx(ctx)
	limit := finResolveLimit(req.Params.Limit)

	var beforeID int64
	if req.Params.Cursor != nil && *req.Params.Cursor != "" {
		var err error
		beforeID, err = finDecodeCursor(*req.Params.Cursor)
		if err != nil {
			return nil, err
		}
	}

	// Resolve account; empty list if wallet never created.
	acctID, _, err := s.WalletSvc.FindAccountByOwnerAnyStatus(ctx, "user", userID, s.DefaultCurrency)
	if err != nil {
		return nil, err
	}
	if acctID == 0 {
		return genfin.ListWalletTransactions200JSONResponse{
			Data:       []genfin.WalletTransaction{},
			Pagination: genfin.CursorPaginationMeta{HasMore: false},
		}, nil
	}

	// Fetch limit+1 to detect has_more.
	entries, err := s.WalletSvc.ListEntriesByAccount(ctx, acctID, limit+1, beforeID)
	if err != nil {
		return nil, err
	}

	hasMore := len(entries) > limit
	if hasMore {
		entries = entries[:limit]
	}

	txns := make([]genfin.WalletTransaction, 0, len(entries))
	for _, e := range entries {
		txn := genfin.WalletTransaction{
			Id:          e.ID,
			AmountMinor: e.AmountMinor,
			Currency:    s.DefaultCurrency,
			OccurredAt:  e.CreatedAt,
			Type:        directionToTxnType(e.Direction),
		}
		if e.TxnType != "" {
			desc := e.TxnType
			txn.Description = &desc
			refType := txnTypeToReferenceType(e.TxnType)
			if refType != nil {
				txn.ReferenceType = refType
			}
		}
		// transactions.reference holds the plan_id string for cashback payments.
		if e.TxnReference != "" {
			if id, parseErr := strconv.ParseInt(e.TxnReference, 10, 64); parseErr == nil {
				txn.ReferenceId = &id
			}
		}
		txns = append(txns, txn)
	}

	resp := genfin.ListWalletTransactions200JSONResponse{
		Data:       txns,
		Pagination: genfin.CursorPaginationMeta{HasMore: hasMore},
	}
	if hasMore && len(entries) > 0 {
		cursor := finEncodeCursor(entries[len(entries)-1].ID)
		resp.Pagination.NextCursor = &cursor
	}
	return resp, nil
}

// ── Cashback ───────────────────────────────────────────────────────────────────

// ListCashbackPlans returns a cursor-paginated list of cashback plans for the
// authenticated user.
func (s *FinServer) ListCashbackPlans(ctx context.Context, req genfin.ListCashbackPlansRequestObject) (genfin.ListCashbackPlansResponseObject, error) {
	userID := identitymw.UserIDFromCtx(ctx)
	limit := finResolveLimit(req.Params.Limit)

	var beforeID int64
	if req.Params.Cursor != nil && *req.Params.Cursor != "" {
		var err error
		beforeID, err = finDecodeCursor(*req.Params.Cursor)
		if err != nil {
			return nil, err
		}
	}

	var status *cashback.PlanStatus
	if req.Params.Status != nil {
		s := cashback.PlanStatus(string(*req.Params.Status))
		status = &s
	}

	plans, err := s.CashbackRepo.ListPlansByUserID(ctx, userID, limit+1, beforeID, status)
	if err != nil {
		return nil, err
	}

	hasMore := len(plans) > limit
	if hasMore {
		plans = plans[:limit]
	}

	data := make([]genfin.CashbackPlan, 0, len(plans))
	for _, p := range plans {
		data = append(data, planToAPI(p))
	}

	resp := genfin.ListCashbackPlans200JSONResponse{
		Data:       data,
		Pagination: genfin.CursorPaginationMeta{HasMore: hasMore},
	}
	if hasMore && len(plans) > 0 {
		cursor := finEncodeCursor(plans[len(plans)-1].ID)
		resp.Pagination.NextCursor = &cursor
	}
	return resp, nil
}

// GetCashbackPlan returns a single cashback plan scoped to the authenticated user.
// Returns 404 if the plan does not exist OR belongs to a different user (IDOR prevention).
func (s *FinServer) GetCashbackPlan(ctx context.Context, req genfin.GetCashbackPlanRequestObject) (genfin.GetCashbackPlanResponseObject, error) {
	userID := identitymw.UserIDFromCtx(ctx)
	plan, err := s.CashbackRepo.GetPlanByIDAndUserID(ctx, req.Id, userID)
	if err != nil {
		if errors.Is(err, cashback.ErrPlanNotFound) {
			return genfin.GetCashbackPlan404JSONResponse{}, nil
		}
		return nil, err
	}
	resp := genfin.GetCashbackPlan200JSONResponse(planToAPI(plan))
	return resp, nil
}

// ListCashbackPayments returns a cursor-paginated list of monthly payments for a
// cashback plan. Returns 404 if the plan does not belong to the authenticated user.
func (s *FinServer) ListCashbackPayments(ctx context.Context, req genfin.ListCashbackPaymentsRequestObject) (genfin.ListCashbackPaymentsResponseObject, error) {
	userID := identitymw.UserIDFromCtx(ctx)
	limit := finResolveLimit(req.Params.Limit)

	// IDOR check: verify plan ownership before listing payments.
	plan, err := s.CashbackRepo.GetPlanByIDAndUserID(ctx, req.Id, userID)
	if err != nil {
		if errors.Is(err, cashback.ErrPlanNotFound) {
			return genfin.ListCashbackPayments404JSONResponse{}, nil
		}
		return nil, err
	}

	var beforeID int64
	if req.Params.Cursor != nil && *req.Params.Cursor != "" {
		beforeID, err = finDecodeCursor(*req.Params.Cursor)
		if err != nil {
			return nil, err
		}
	}

	payments, err := s.CashbackRepo.ListPaymentsByPlanID(ctx, req.Id, limit+1, beforeID)
	if err != nil {
		return nil, err
	}

	hasMore := len(payments) > limit
	if hasMore {
		payments = payments[:limit]
	}

	data := make([]genfin.CashbackPayment, 0, len(payments))
	for _, pay := range payments {
		data = append(data, paymentToAPI(pay, plan.Currency))
	}

	resp := genfin.ListCashbackPayments200JSONResponse{
		Data:       data,
		Pagination: genfin.CursorPaginationMeta{HasMore: hasMore},
	}
	if hasMore && len(payments) > 0 {
		cursor := finEncodeCursor(payments[len(payments)-1].ID)
		resp.Pagination.NextCursor = &cursor
	}
	return resp, nil
}

// ── mapping helpers ────────────────────────────────────────────────────────────

// planToAPI maps a cashback.Plan to the OpenAPI CashbackPlan model.
// product_id=0, product_title="Sipariş #<orderID>", product_image_url=nil are
// Phase 4.3a fallbacks; Phase 4.3b adds migration + event enrichment.
func planToAPI(p cashback.Plan) genfin.CashbackPlan {
	productTitle := fmt.Sprintf("Sipariş #%d", p.OrderID)
	return genfin.CashbackPlan{
		Id:                       p.ID,
		OrderId:                  p.OrderID,
		MonthlyAmountMinor:       p.MonthlyAmountMinor,
		Currency:                 p.Currency,
		ReferenceInterestRateBps: p.ReferenceInterestRateBps,
		StartDate:                openapi_types.Date{Time: p.StartDate},
		Status:                   genfin.CashbackPlanStatus(string(p.Status)),
		CreatedAt:                p.CreatedAt,
		// Phase 4.3a fallbacks (product_id=0 means data unavailable; see DEVELOPMENT.md).
		ProductId:       0,
		ProductTitle:    productTitle,
		ProductImageUrl: nil,
	}
}

// paymentToAPI maps a cashback.Payment to the OpenAPI CashbackPayment model.
// currency is taken from the parent plan (cashback_schema.payments has no currency column).
func paymentToAPI(pay cashback.Payment, currency string) genfin.CashbackPayment {
	return genfin.CashbackPayment{
		Id:           pay.ID,
		PlanId:       pay.PlanID,
		AmountMinor:  pay.AmountMinor,
		Currency:     currency,
		PeriodYyyymm: strconv.Itoa(pay.PeriodYYYYMM),
		Status:       genfin.CashbackPaymentStatus(pay.Status),
		PaidAt:       pay.PaidDate,
	}
}

// directionToTxnType maps a ledger direction to the OpenAPI WalletTransactionType.
// "C" (credit to the user's account) = incoming = "credit"; "D" = "debit".
func directionToTxnType(direction string) genfin.WalletTransactionType {
	if direction == "C" {
		return genfin.Credit
	}
	return genfin.Debit
}

// txnTypeToReferenceType maps a transaction type string to its OpenAPI reference type.
func txnTypeToReferenceType(txnType string) *genfin.WalletTransactionReferenceType {
	switch txnType {
	case "cashback_payment":
		t := genfin.WalletTransactionReferenceTypeCashbackPayment
		return &t
	case "seller_payout":
		t := genfin.WalletTransactionReferenceTypePayout
		return &t
	default:
		return nil
	}
}

// compile-time interface check
var _ genfin.StrictServerInterface = (*FinServer)(nil)
