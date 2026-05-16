package cashback

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/pkg/timex"
)

// ReferenceInterestRateBpsConst is the v6 LOCKED perpetual reference interest rate.
// 5000 bps = 50.00%. Snapshotted per plan at creation; NEVER changed for existing plans.
// CLAUDE.md § 4.7.
const ReferenceInterestRateBpsConst = 5000

type cashbackService struct {
	repo             Repository
	outbox           outbox.Repository
	calLoader        timex.CalendarLoader
	walletPoster     WalletPoster
	log              *slog.Logger
	cashbackCurrency string // coin currency code; read from env DEFAULT_CASHBACK_CURRENCY at startup
}

// NewService constructs a cashback Service.
// cashbackCurrency should come from env DEFAULT_CASHBACK_CURRENCY (e.g. TRY_COIN).
// walletPoster is satisfied by wallet.Service (injected by fin-svc/main.go via Commit 7).
func NewService(
	repo Repository,
	outboxRepo outbox.Repository,
	calLoader timex.CalendarLoader,
	cashbackCurrency string,
	walletPoster WalletPoster,
	log *slog.Logger,
) Service {
	if log == nil {
		log = slog.Default()
	}
	return &cashbackService{
		repo:             repo,
		outbox:           outboxRepo,
		calLoader:        calLoader,
		cashbackCurrency: cashbackCurrency,
		walletPoster:     walletPoster,
		log:              log,
	}
}

func (s *cashbackService) CreatePlanForOrder(ctx context.Context, ev OrderDeliveredEvent) error {
	// 1. Idempotency: if a plan already exists for this order, no-op.
	_, err := s.repo.FindPlanByOrderID(ctx, ev.OrderID)
	if err == nil {
		return nil
	}
	if err != ErrPlanNotFound {
		return fmt.Errorf("cashback: idempotency check order %d: %w", ev.OrderID, err)
	}

	// 2. Sum commission_amount_minor across all items.
	var totalCommissionMinor int64
	for _, it := range ev.Items {
		totalCommissionMinor += it.CommissionAmountMinor
	}
	if totalCommissionMinor == 0 {
		slog.Warn("cashback: zero total commission, skipping plan",
			"order_id", ev.OrderID)
		return nil
	}

	// 3. v6 PERPETUAL formula — integer arithmetic only (CLAUDE.md § 4.6 + § 10.7).
	// yearly_yield = commission × reference_rate_bps / 10000
	// monthly_coin = yearly_yield / 12
	yearlyYieldMinor := totalCommissionMinor * int64(ReferenceInterestRateBpsConst) / 10000
	monthlyMinor := yearlyYieldMinor / 12
	if monthlyMinor == 0 {
		slog.Warn("cashback: monthly_amount rounds to zero, skipping plan",
			"order_id", ev.OrderID, "total_commission_minor", totalCommissionMinor)
		return nil
	}

	// 4. start_date = delivered_at + 3 business days (CLAUDE.md § 4.7).
	cal, err := s.calLoader.Load(ctx, ev.Market)
	if err != nil {
		return fmt.Errorf("cashback: load calendar for %s: %w", ev.Market, err)
	}
	startDate := timex.AddBusinessDays(ev.DeliveredAt, 3, cal)

	// 5. Serialize commission snapshot for JSONB audit column.
	snapshot, err := json.Marshal(ev.Items)
	if err != nil {
		return fmt.Errorf("cashback: marshal commission snapshot order %d: %w", ev.OrderID, err)
	}

	p := Plan{
		OrderID:                  ev.OrderID,
		UserID:                   ev.UserID,
		MonthlyAmountMinor:       monthlyMinor,
		Currency:                 s.cashbackCurrency,
		ReferenceInterestRateBps: ReferenceInterestRateBpsConst,
		StartDate:                startDate,
		Status:                   PlanStatusActive,
		DeliveredAt:              ev.DeliveredAt,
		Market:                   ev.Market,
		CommissionSnapshot:       json.RawMessage(snapshot),
		IdempotencyKey:           fmt.Sprintf("cashback:plan:order_%d", ev.OrderID),
	}

	outboxKey := fmt.Sprintf("fin:cashback:plan:created:order_%d", ev.OrderID)

	// 6. Persist plan + outbox event in a single transaction (CLAUDE.md § 4.5).
	return s.repo.WithTx(ctx, pgx.ReadCommitted, func(tx pgx.Tx) error {
		created, txErr := s.repo.InsertPlan(ctx, tx, p)
		if txErr != nil {
			return txErr
		}

		payload, marshalErr := json.Marshal(planCreatedPayload{
			PlanID:             created.ID,
			OrderID:            created.OrderID,
			UserID:             created.UserID,
			MonthlyAmountMinor: created.MonthlyAmountMinor,
			Currency:           created.Currency,
			StartDate:          created.StartDate.Format("2006-01-02"),
			Market:             created.Market,
		})
		if marshalErr != nil {
			return fmt.Errorf("cashback: marshal plan_created payload: %w", marshalErr)
		}

		return s.outbox.Insert(ctx, tx, outbox.Row{
			Aggregate:      "cashback",
			EventType:      "fin.cashback.plan.created.v1",
			Payload:        json.RawMessage(payload),
			IdempotencyKey: outboxKey,
			Market:         created.Market,
			Currency:       created.Currency,
		})
	})
}

// RunMonth processes all active plans due for period (YYYYMM) as of asOf.
// Full implementation below — see processPlan/processPlanInTx.
func (s *cashbackService) RunMonth(ctx context.Context, period int, asOf time.Time, currency string) (RunMonthResult, error) {
	return s.runMonth(ctx, period, asOf, currency)
}

type planCreatedPayload struct {
	PlanID             int64  `json:"plan_id"`
	OrderID            int64  `json:"order_id"`
	UserID             int64  `json:"user_id"`
	MonthlyAmountMinor int64  `json:"monthly_amount_minor"`
	Currency           string `json:"currency"`
	StartDate          string `json:"start_date"`
	Market             string `json:"market"`
}
