package cashback

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxCashbackRepository struct {
	pool *pgxpool.Pool
}

// NewRepository constructs a Repository backed by pool.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxCashbackRepository{pool: pool}
}

// WithTx runs fn inside a transaction at the given isolation level.
// Retries up to 3 times on pgError 40001 (serialization failure).
func (r *pgxCashbackRepository) WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	const maxRetries = 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: level})
		if err != nil {
			return fmt.Errorf("cashback: begin tx: %w", err)
		}
		err = fn(tx)
		if err != nil {
			_ = tx.Rollback(ctx)
			if isSerializationFailure(err) && attempt < maxRetries-1 {
				continue
			}
			return err
		}
		if commitErr := tx.Commit(ctx); commitErr != nil {
			if isSerializationFailure(commitErr) && attempt < maxRetries-1 {
				continue
			}
			return fmt.Errorf("cashback: commit tx: %w", commitErr)
		}
		return nil
	}
	return ErrMaxRetriesExceeded
}

// InsertPlanIfAbsent inserts p within tx. Returns (plan, true, nil) on success.
// Returns (existing, false, nil) when order_id already exists (idempotent re-delivery).
// The caller is expected to have started a ReadCommitted tx via WithTx.
func (r *pgxCashbackRepository) InsertPlanIfAbsent(ctx context.Context, tx pgx.Tx, p Plan) (Plan, bool, error) {
	const q = `
		INSERT INTO cashback_schema.plans
			(order_id, user_id, price_minor, commission_bps, currency,
			 total_months, monthly_amount_minor, monthly_amount_last_minor,
			 start_date, status, delivered_at, market,
			 commission_snapshot, idempotency_key,
			 product_id, product_title, product_image_url)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
		ON CONFLICT (order_id) DO NOTHING
		RETURNING id, created_at, updated_at`

	var productID *int64
	if p.ProductID != 0 {
		productID = &p.ProductID
	}
	var productTitle *string
	if p.ProductTitle != "" {
		productTitle = &p.ProductTitle
	}
	var productImageURL *string
	if p.ProductImageURL != "" {
		productImageURL = &p.ProductImageURL
	}

	err := tx.QueryRow(ctx, q,
		p.OrderID, p.UserID, p.PriceMinor, p.CommissionBps, p.Currency,
		p.TotalMonths, p.MonthlyAmountMinor, p.MonthlyAmountLastMinor,
		p.StartDate, string(p.Status), p.DeliveredAt.UTC(), p.Market,
		[]byte(p.CommissionSnapshot), p.IdempotencyKey,
		productID, productTitle, productImageURL,
	).Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)

	if errors.Is(err, pgx.ErrNoRows) {
		// ON CONFLICT DO NOTHING returned nothing — plan already exists. Fetch and return it.
		existing, fetchErr := r.fetchPlanByOrderID(ctx, p.OrderID)
		if fetchErr != nil {
			return Plan{}, false, fmt.Errorf("cashback: fetch existing plan order=%d: %w", p.OrderID, fetchErr)
		}
		return existing, false, nil
	}
	if err != nil {
		return Plan{}, false, fmt.Errorf("cashback: InsertPlanIfAbsent order=%d: %w", p.OrderID, err)
	}
	return p, true, nil
}

// fetchPlanByOrderID is an internal helper used by InsertPlanIfAbsent on conflict.
func (r *pgxCashbackRepository) fetchPlanByOrderID(ctx context.Context, orderID int64) (Plan, error) {
	const q = `
		SELECT id, order_id, user_id, price_minor, commission_bps, currency,
		       total_months, monthly_amount_minor, monthly_amount_last_minor, payments_made,
		       start_date, status, delivered_at, market,
		       commission_snapshot, idempotency_key,
		       COALESCE(product_id,0), COALESCE(product_title,''), COALESCE(product_image_url,''),
		       created_at, updated_at
		FROM cashback_schema.plans
		WHERE order_id = $1
		LIMIT 1`

	var p Plan
	var statusStr string
	var snapshot []byte
	err := r.pool.QueryRow(ctx, q, orderID).Scan(
		&p.ID, &p.OrderID, &p.UserID, &p.PriceMinor, &p.CommissionBps, &p.Currency,
		&p.TotalMonths, &p.MonthlyAmountMinor, &p.MonthlyAmountLastMinor, &p.PaymentsMade,
		&p.StartDate, &statusStr, &p.DeliveredAt, &p.Market,
		&snapshot, &p.IdempotencyKey,
		&p.ProductID, &p.ProductTitle, &p.ProductImageURL,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Plan{}, ErrPlanNotFound
		}
		return Plan{}, err
	}
	p.Status = PlanStatus(statusStr)
	p.CommissionSnapshot = snapshot
	return p, nil
}

// ListDuePlans returns up to limit active plans whose next installment is due by runDate
// AND have not yet been paid for runPeriodYYYYMM. The period filter via NOT EXISTS
// keeps the cron's per-call cost bounded as payments accumulate.
// Uses FOR UPDATE SKIP LOCKED so concurrent cron instances don't double-process.
func (r *pgxCashbackRepository) ListDuePlans(ctx context.Context, runDate time.Time, runPeriodYYYYMM int, limit int) ([]Plan, error) {
	const q = `
		SELECT p.id, p.order_id, p.user_id, p.price_minor, p.commission_bps, p.currency,
		       p.total_months, p.monthly_amount_minor, p.monthly_amount_last_minor, p.payments_made,
		       p.start_date, p.status, p.delivered_at, p.market,
		       p.commission_snapshot, p.idempotency_key,
		       COALESCE(p.product_id,0), COALESCE(p.product_title,''), COALESCE(p.product_image_url,''),
		       p.created_at, p.updated_at
		FROM cashback_schema.plans p
		WHERE p.status = 'active'
		  AND p.payments_made < p.total_months
		  AND (p.start_date + (p.payments_made * INTERVAL '1 month')) <= $1
		  AND NOT EXISTS (
		      SELECT 1 FROM cashback_schema.payments pay
		      WHERE pay.plan_id = p.id AND pay.period_yyyymm = $2
		  )
		ORDER BY p.id
		LIMIT $3
		FOR UPDATE SKIP LOCKED`

	rows, err := r.pool.Query(ctx, q, runDate, runPeriodYYYYMM, limit)
	if err != nil {
		return nil, fmt.Errorf("cashback: ListDuePlans: %w", err)
	}
	defer rows.Close()

	var plans []Plan
	for rows.Next() {
		var p Plan
		var statusStr string
		var snapshot []byte
		if err := rows.Scan(
			&p.ID, &p.OrderID, &p.UserID, &p.PriceMinor, &p.CommissionBps, &p.Currency,
			&p.TotalMonths, &p.MonthlyAmountMinor, &p.MonthlyAmountLastMinor, &p.PaymentsMade,
			&p.StartDate, &statusStr, &p.DeliveredAt, &p.Market,
			&snapshot, &p.IdempotencyKey,
			&p.ProductID, &p.ProductTitle, &p.ProductImageURL,
			&p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("cashback: ListDuePlans scan: %w", err)
		}
		p.Status = PlanStatus(statusStr)
		p.CommissionSnapshot = snapshot
		plans = append(plans, p)
	}
	return plans, rows.Err()
}

// PaymentExistsForPeriod is the cheap read-side fast-path mate to
// ClaimPaymentPeriod. Uses the pool (not the tx) for max concurrency.
func (r *pgxCashbackRepository) PaymentExistsForPeriod(ctx context.Context, planID int64, periodYYYYMM int) (bool, error) {
	const q = `SELECT EXISTS (
		SELECT 1 FROM cashback_schema.payments
		WHERE plan_id = $1 AND period_yyyymm = $2
	)`
	var exists bool
	if err := r.pool.QueryRow(ctx, q, planID, periodYYYYMM).Scan(&exists); err != nil {
		return false, fmt.Errorf("cashback: PaymentExistsForPeriod plan=%d period=%d: %w", planID, periodYYYYMM, err)
	}
	return exists, nil
}

// ClaimPaymentPeriod INSERTs a 'scheduled' payment row inside tx. Uses
// ON CONFLICT DO NOTHING against UNIQUE(plan_id, period_yyyymm) — the v6
// storage-layer idempotency guard. Concurrent racers serialize here: the
// winner sees claimed=true with a new payment id; the loser sees claimed=false
// and must skip PostInTx and the cache refresh.
func (r *pgxCashbackRepository) ClaimPaymentPeriod(ctx context.Context, tx pgx.Tx, in ClaimPaymentInput) (int64, bool, error) {
	const q = `
		INSERT INTO cashback_schema.payments
		    (plan_id, period_yyyymm, scheduled_date, amount_minor, status, idempotency_key, attempt_count)
		VALUES ($1, $2, $3, $4, 'scheduled', $5, 1)
		ON CONFLICT DO NOTHING
		RETURNING id`

	var id int64
	err := tx.QueryRow(ctx, q,
		in.PlanID, in.PeriodYYYYMM, in.ScheduledDate.UTC(), in.AmountMinor, in.IdempotencyKey,
	).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, false, nil
	}
	if err != nil {
		// Defensive: if ON CONFLICT didn't catch a 23505 (e.g., constraint name
		// drift), treat the unique violation as a clean race-lost outcome.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return 0, false, nil
		}
		return 0, false, fmt.Errorf("cashback: ClaimPaymentPeriod plan=%d period=%d: %w", in.PlanID, in.PeriodYYYYMM, err)
	}
	return id, true, nil
}

// MarkPaymentPaid flips the row from 'scheduled' to 'paid' and stamps it with
// the ledger transaction id and paid_date. Called inside the same tx as
// ClaimPaymentPeriod, after PostInTx returns successfully.
func (r *pgxCashbackRepository) MarkPaymentPaid(ctx context.Context, tx pgx.Tx, paymentID int64, ledgerTxnID int64, paidDate time.Time) error {
	const q = `
		UPDATE cashback_schema.payments
		SET status                = 'paid',
		    ledger_transaction_id = $2,
		    paid_date             = $3
		WHERE id = $1`

	tag, err := tx.Exec(ctx, q, paymentID, ledgerTxnID, paidDate.UTC())
	if err != nil {
		return fmt.Errorf("cashback: MarkPaymentPaid payment=%d: %w", paymentID, err)
	}
	if tag.RowsAffected() != 1 {
		return fmt.Errorf("cashback: MarkPaymentPaid payment=%d: rows_affected=%d (want 1)", paymentID, tag.RowsAffected())
	}
	return nil
}

// IncrPaymentsMade atomically increments payments_made by 1 within tx.
// Sets status='completed' when the new count equals total_months.
// Returns (newCount, completed, nil) on success.
// NOTE: commit 2 of this PR replaces this with COUNT-derived RefreshPaymentsMadeCache.
func (r *pgxCashbackRepository) IncrPaymentsMade(ctx context.Context, tx pgx.Tx, planID int64) (int, bool, error) {
	const q = `
		UPDATE cashback_schema.plans
		SET payments_made = payments_made + 1,
		    status        = CASE WHEN payments_made + 1 >= total_months THEN 'completed' ELSE status END,
		    updated_at    = now()
		WHERE id = $1
		RETURNING payments_made, (payments_made >= total_months) AS completed`

	var newCount int
	var completed bool
	err := tx.QueryRow(ctx, q, planID).Scan(&newCount, &completed)
	if err != nil {
		return 0, false, fmt.Errorf("cashback: IncrPaymentsMade plan=%d: %w", planID, err)
	}
	return newCount, completed, nil
}

// GetPlan fetches a plan by primary key, scoped to userID for IDOR prevention.
// Returns ErrPlanNotFound when no row matches — callers must return 404, NOT 403.
func (r *pgxCashbackRepository) GetPlan(ctx context.Context, userID, planID int64) (Plan, error) {
	const q = `
		SELECT id, order_id, user_id, price_minor, commission_bps, currency,
		       total_months, monthly_amount_minor, monthly_amount_last_minor, payments_made,
		       reference_interest_rate_bps,
		       start_date, status, delivered_at, market,
		       commission_snapshot, idempotency_key,
		       COALESCE(product_id,0), COALESCE(product_title,''), COALESCE(product_image_url,''),
		       created_at, updated_at
		FROM cashback_schema.plans
		WHERE id = $1 AND user_id = $2`

	var p Plan
	var statusStr string
	var snapshot []byte
	err := r.pool.QueryRow(ctx, q, planID, userID).Scan(
		&p.ID, &p.OrderID, &p.UserID, &p.PriceMinor, &p.CommissionBps, &p.Currency,
		&p.TotalMonths, &p.MonthlyAmountMinor, &p.MonthlyAmountLastMinor, &p.PaymentsMade,
		&p.ReferenceInterestRateBps,
		&p.StartDate, &statusStr, &p.DeliveredAt, &p.Market,
		&snapshot, &p.IdempotencyKey,
		&p.ProductID, &p.ProductTitle, &p.ProductImageURL,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Plan{}, ErrPlanNotFound
		}
		return Plan{}, fmt.Errorf("cashback: GetPlan plan=%d user=%d: %w", planID, userID, err)
	}
	p.Status = PlanStatus(statusStr)
	p.CommissionSnapshot = snapshot
	return p, nil
}

// ListPlansByUser returns up to limit plans for userID, ordered by id DESC.
// Pass beforeID > 0 to cursor-paginate. Pass non-nil status to filter by status.
func (r *pgxCashbackRepository) ListPlansByUser(ctx context.Context, userID int64, limit int, beforeID int64, status *PlanStatus) ([]Plan, error) {
	var statusVal *string
	if status != nil {
		s := string(*status)
		statusVal = &s
	}
	rows, err := r.pool.Query(ctx,
		`SELECT id, order_id, user_id, price_minor, commission_bps, currency,
		        total_months, monthly_amount_minor, monthly_amount_last_minor, payments_made,
		        reference_interest_rate_bps,
		        start_date, status, delivered_at, market,
		        commission_snapshot, idempotency_key,
		        COALESCE(product_id,0), COALESCE(product_title,''), COALESCE(product_image_url,''),
		        created_at, updated_at
		 FROM cashback_schema.plans
		 WHERE user_id = $1
		   AND ($2 = 0 OR id < $2)
		   AND ($3::text IS NULL OR status = $3)
		 ORDER BY id DESC
		 LIMIT $4`,
		userID, beforeID, statusVal, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("cashback: ListPlansByUser user=%d: %w", userID, err)
	}
	defer rows.Close()

	var plans []Plan
	for rows.Next() {
		var p Plan
		var statusStr string
		var snapshot []byte
		if err := rows.Scan(
			&p.ID, &p.OrderID, &p.UserID, &p.PriceMinor, &p.CommissionBps, &p.Currency,
			&p.TotalMonths, &p.MonthlyAmountMinor, &p.MonthlyAmountLastMinor, &p.PaymentsMade,
			&p.ReferenceInterestRateBps,
			&p.StartDate, &statusStr, &p.DeliveredAt, &p.Market,
			&snapshot, &p.IdempotencyKey,
			&p.ProductID, &p.ProductTitle, &p.ProductImageURL,
			&p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("cashback: ListPlansByUser scan user=%d: %w", userID, err)
		}
		p.Status = PlanStatus(statusStr)
		p.CommissionSnapshot = snapshot
		plans = append(plans, p)
	}
	return plans, rows.Err()
}

// ListPaymentsByPlanID returns up to limit payments for planID, ordered by id DESC.
// Kept for backward compat with the fin HTTP API; v8 plans have no payment rows.
func (r *pgxCashbackRepository) ListPaymentsByPlanID(ctx context.Context, planID int64, limit int, beforeID int64) ([]Payment, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, plan_id, period_yyyymm, scheduled_date, paid_date,
		        amount_minor, status, ledger_transaction_id, idempotency_key,
		        attempt_count, last_attempt_at, last_error, created_at
		 FROM cashback_schema.payments
		 WHERE plan_id = $1
		   AND ($2 = 0 OR id < $2)
		 ORDER BY id DESC
		 LIMIT $3`,
		planID, beforeID, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("cashback: ListPaymentsByPlanID plan=%d: %w", planID, err)
	}
	defer rows.Close()

	var payments []Payment
	for rows.Next() {
		var pay Payment
		if err := rows.Scan(
			&pay.ID, &pay.PlanID, &pay.PeriodYYYYMM, &pay.ScheduledDate, &pay.PaidDate,
			&pay.AmountMinor, &pay.Status, &pay.LedgerTransactionID, &pay.IdempotencyKey,
			&pay.AttemptCount, &pay.LastAttemptAt, &pay.LastError, &pay.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("cashback: ListPaymentsByPlanID scan plan=%d: %w", planID, err)
		}
		payments = append(payments, pay)
	}
	return payments, rows.Err()
}

func isSerializationFailure(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "40001"
}
