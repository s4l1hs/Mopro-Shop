package cashback

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/pkg/metrics"
	"github.com/mopro/platform/pkg/timex"
)

type cashbackService struct {
	repo             Repository
	outbox           outbox.Repository
	calLoader        timex.CalendarLoader
	walletPoster     WalletPoster
	log              *slog.Logger
	cashbackCurrency string                   // coin currency code, read from env DEFAULT_CASHBACK_CURRENCY
	biz              *metrics.BusinessMetrics // nil disables business KPI counters
}

// NewService constructs a cashback Service.
// cashbackCurrency should come from env DEFAULT_CASHBACK_CURRENCY (e.g. "TRY_COIN").
// calLoader is used to compute start_date = deliveredAt + 3 business days.
// biz is optional (nil disables business KPI metrics).
func NewService(
	repo Repository,
	outboxRepo outbox.Repository,
	calLoader timex.CalendarLoader,
	cashbackCurrency string,
	walletPoster WalletPoster,
	log *slog.Logger,
	biz *metrics.BusinessMetrics,
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
		biz:              biz,
	}
}

// CreatePlanFromDelivery creates a v8 fixed-term cashback plan for the delivered order.
// Idempotent: returns the existing plan without error if one already exists for ev.OrderID.
func (s *cashbackService) CreatePlanFromDelivery(ctx context.Context, ev OrderDeliveredEvent) (Plan, error) {
	if ev.PriceMinor <= 0 {
		s.log.WarnContext(ctx, "cashback: zero price, skipping plan", "order_id", ev.OrderID)
		return Plan{}, nil
	}

	// 1. Compute fixed-term schedule (pure integer math — see calculator.go).
	terms, err := ComputePlanTerms(ev.PriceMinor, ev.CommissionBps)
	if err != nil {
		return Plan{}, fmt.Errorf("cashback: ComputePlanTerms order=%d price=%d bps=%d: %w",
			ev.OrderID, ev.PriceMinor, ev.CommissionBps, err)
	}

	// 2. start_date = delivered_at + 3 business days (CLAUDE.md §4.7).
	var startDate time.Time
	if s.calLoader != nil {
		cal, calErr := s.calLoader.Load(ctx, ev.Market)
		if calErr != nil {
			return Plan{}, fmt.Errorf("cashback: load calendar %s: %w", ev.Market, calErr)
		}
		startDate = timex.AddBusinessDays(ev.DeliveredAt, 3, cal)
	} else {
		startDate = ev.DeliveredAt.AddDate(0, 0, 3)
	}

	// 3. Serialize commission snapshot for JSONB audit column.
	snapshot, err := json.Marshal(ev.Items)
	if err != nil {
		return Plan{}, fmt.Errorf("cashback: marshal commission snapshot order=%d: %w", ev.OrderID, err)
	}

	p := Plan{
		OrderID:                ev.OrderID,
		UserID:                 ev.UserID,
		PriceMinor:             ev.PriceMinor,
		CommissionBps:          ev.CommissionBps,
		Currency:               s.cashbackCurrency,
		TotalMonths:            terms.TotalMonths,
		MonthlyAmountMinor:     terms.MonthlyAmountMinor,
		MonthlyAmountLastMinor: terms.MonthlyAmountLastMinor,
		Status:                 PlanStatusActive,
		StartDate:              startDate,
		DeliveredAt:            ev.DeliveredAt,
		Market:                 ev.Market,
		CommissionSnapshot:     json.RawMessage(snapshot),
		IdempotencyKey:         fmt.Sprintf("cashback:plan:order_%d", ev.OrderID),
		ProductID:              ev.ProductID,
		ProductTitle:           ev.ProductTitle,
		ProductImageURL:        ev.ProductImageURL,
	}

	outboxKey := fmt.Sprintf("fin:cashback:plan:created:order_%d", ev.OrderID)

	// 4. Persist plan + outbox event in a single READ COMMITTED tx (CLAUDE.md §4.5).
	var created Plan
	var isNew bool
	err = s.repo.WithTx(ctx, pgx.ReadCommitted, func(tx pgx.Tx) error {
		var txErr error
		created, isNew, txErr = s.repo.InsertPlanIfAbsent(ctx, tx, p)
		if txErr != nil {
			return txErr
		}
		if !isNew {
			return nil // idempotent re-delivery: outbox already written
		}
		payload, marshalErr := json.Marshal(planCreatedPayload{
			PlanID:             created.ID,
			OrderID:            created.OrderID,
			UserID:             created.UserID,
			PriceMinor:         created.PriceMinor,
			CommissionBps:      created.CommissionBps,
			TotalMonths:        created.TotalMonths,
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
	if err != nil {
		return Plan{}, err
	}

	if isNew {
		s.log.InfoContext(ctx, "cashback: plan created",
			"plan_id", created.ID,
			"order_id", created.OrderID,
			"user_id", created.UserID,
			"price_minor", created.PriceMinor,
			"commission_bps", created.CommissionBps,
			"T_months", created.TotalMonths,
			"monthly", created.MonthlyAmountMinor,
			"last", created.MonthlyAmountLastMinor,
		)
		s.biz.IncCashbackPlanCreated("fin-svc", created.Market)
	}
	return created, nil
}

// GetPlan returns a single plan scoped to userID (IDOR: returns 404 for cross-user access).
func (s *cashbackService) GetPlan(ctx context.Context, userID, planID int64) (Plan, error) {
	return s.repo.GetPlan(ctx, userID, planID)
}

// ListPlans returns cursor-paginated plans for userID, ordered by id DESC.
func (s *cashbackService) ListPlans(ctx context.Context, userID int64, cursor int64, limit int, status *PlanStatus) ([]Plan, error) {
	return s.repo.ListPlansByUser(ctx, userID, limit, cursor, status)
}

type planCreatedPayload struct {
	PlanID             int64  `json:"plan_id"`
	OrderID            int64  `json:"order_id"`
	UserID             int64  `json:"user_id"`
	PriceMinor         int64  `json:"price_minor"`
	CommissionBps      int    `json:"commission_bps"`
	TotalMonths        int    `json:"total_months"`
	MonthlyAmountMinor int64  `json:"monthly_amount_minor"`
	Currency           string `json:"currency"`
	StartDate          string `json:"start_date"`
	Market             string `json:"market"`
}
