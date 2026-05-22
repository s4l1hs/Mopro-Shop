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
// Retries up to 3 times on pgError 40001 (serialization failure) —
// matching the pattern in wallet/repository.go.
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

func (r *pgxCashbackRepository) InsertPlan(ctx context.Context, tx pgx.Tx, p Plan) (Plan, error) {
	const q = `
		INSERT INTO cashback_schema.plans
			(order_id, user_id, monthly_amount_minor, currency,
			 reference_interest_rate_bps, start_date, status,
			 delivered_at, market, commission_snapshot, idempotency_key,
			 product_id, product_title, product_image_url)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
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
		p.OrderID, p.UserID, p.MonthlyAmountMinor, p.Currency,
		p.ReferenceInterestRateBps, p.StartDate,
		string(p.Status), p.DeliveredAt.UTC(), p.Market,
		[]byte(p.CommissionSnapshot), p.IdempotencyKey,
		productID, productTitle, productImageURL,
	).Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Plan{}, ErrPlanAlreadyExists
		}
		return Plan{}, err
	}
	return p, nil
}

func (r *pgxCashbackRepository) FindPlanByOrderID(ctx context.Context, orderID int64) (Plan, error) {
	const q = `
		SELECT id, order_id, user_id, monthly_amount_minor, currency,
		       reference_interest_rate_bps, start_date, status,
		       delivered_at, market, commission_snapshot, idempotency_key,
		       product_id, product_title, product_image_url,
		       created_at, updated_at
		FROM cashback_schema.plans
		WHERE order_id = $1
		LIMIT 1`

	var p Plan
	var statusStr string
	var snapshot []byte
	var productID *int64
	var productTitle, productImageURL *string

	err := r.pool.QueryRow(ctx, q, orderID).Scan(
		&p.ID, &p.OrderID, &p.UserID, &p.MonthlyAmountMinor, &p.Currency,
		&p.ReferenceInterestRateBps, &p.StartDate, &statusStr,
		&p.DeliveredAt, &p.Market, &snapshot, &p.IdempotencyKey,
		&productID, &productTitle, &productImageURL,
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
	if productID != nil {
		p.ProductID = *productID
	}
	if productTitle != nil {
		p.ProductTitle = *productTitle
	}
	if productImageURL != nil {
		p.ProductImageURL = *productImageURL
	}
	return p, nil
}

// FetchPlansBatch returns up to batchSize active plans due for period as of asOf,
// using FOR UPDATE SKIP LOCKED so concurrent cron instances don't double-process.
// The outer tx must be READ COMMITTED and committed immediately after the SELECT
// to release locks (the caller is responsible for committing before processing each plan).
func (r *pgxCashbackRepository) FetchPlansBatch(ctx context.Context, period int, asOf time.Time, currency string, batchSize int) ([]Plan, error) {
	const q = `
		SELECT id, order_id, user_id, monthly_amount_minor, currency,
		       reference_interest_rate_bps, start_date, status,
		       delivered_at, market, commission_snapshot, idempotency_key,
		       product_id, product_title, product_image_url,
		       created_at, updated_at, last_distributed_period
		FROM cashback_schema.plans
		WHERE status = 'active'
		  AND currency = $1
		  AND start_date <= $2
		  AND (last_distributed_period IS NULL OR last_distributed_period < $3)
		ORDER BY id
		LIMIT $4
		FOR UPDATE SKIP LOCKED`

	rows, err := r.pool.Query(ctx, q, currency, asOf, period, batchSize)
	if err != nil {
		return nil, fmt.Errorf("cashback: FetchPlansBatch: %w", err)
	}
	defer rows.Close()

	var plans []Plan
	for rows.Next() {
		var p Plan
		var statusStr string
		var snapshot []byte
		var productID *int64
		var productTitle, productImageURL *string
		var lastPeriod *int
		if err := rows.Scan(
			&p.ID, &p.OrderID, &p.UserID, &p.MonthlyAmountMinor, &p.Currency,
			&p.ReferenceInterestRateBps, &p.StartDate, &statusStr,
			&p.DeliveredAt, &p.Market, &snapshot, &p.IdempotencyKey,
			&productID, &productTitle, &productImageURL,
			&p.CreatedAt, &p.UpdatedAt, &lastPeriod,
		); err != nil {
			return nil, fmt.Errorf("cashback: FetchPlansBatch scan: %w", err)
		}
		p.Status = PlanStatus(statusStr)
		p.CommissionSnapshot = snapshot
		if productID != nil {
			p.ProductID = *productID
		}
		if productTitle != nil {
			p.ProductTitle = *productTitle
		}
		if productImageURL != nil {
			p.ProductImageURL = *productImageURL
		}
		plans = append(plans, p)
	}
	return plans, rows.Err()
}

// InsertPayment inserts a cashback_schema.payments row within tx.
// Uses SAVEPOINT so a 23505 (duplicate period) does not abort the outer tx.
// Returns (Payment{}, ErrPaymentAlreadyExists) on duplicate.
func (r *pgxCashbackRepository) InsertPayment(ctx context.Context, tx pgx.Tx, pay Payment) (Payment, error) {
	if _, err := tx.Exec(ctx, "SAVEPOINT insert_payment"); err != nil {
		return Payment{}, fmt.Errorf("cashback: savepoint insert_payment: %w", err)
	}

	const q = `
		INSERT INTO cashback_schema.payments
			(plan_id, period_yyyymm, scheduled_date, amount_minor, status, idempotency_key)
		VALUES ($1, $2, $3, $4, 'scheduled', $5)
		RETURNING id, created_at`

	err := tx.QueryRow(ctx, q,
		pay.PlanID, pay.PeriodYYYYMM, pay.ScheduledDate, pay.AmountMinor, pay.IdempotencyKey,
	).Scan(&pay.ID, &pay.CreatedAt)
	if err != nil {
		_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT insert_payment")
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Payment{}, ErrPaymentAlreadyExists
		}
		return Payment{}, fmt.Errorf("cashback: InsertPayment plan=%d period=%d: %w", pay.PlanID, pay.PeriodYYYYMM, err)
	}

	if _, err := tx.Exec(ctx, "RELEASE SAVEPOINT insert_payment"); err != nil {
		return Payment{}, fmt.Errorf("cashback: release savepoint insert_payment: %w", err)
	}
	return pay, nil
}

// MarkPaymentPaid updates status='paid', sets ledger_transaction_id and paid_date.
func (r *pgxCashbackRepository) MarkPaymentPaid(ctx context.Context, tx pgx.Tx, paymentID int64, ledgerTxnID int64, paidDate time.Time) error {
	_, err := tx.Exec(ctx,
		`UPDATE cashback_schema.payments
		 SET status='paid', ledger_transaction_id=$1, paid_date=$2,
		     last_attempt_at=now(), attempt_count=attempt_count+1
		 WHERE id=$3`,
		ledgerTxnID, paidDate.UTC(), paymentID,
	)
	if err != nil {
		return fmt.Errorf("cashback: MarkPaymentPaid id=%d: %w", paymentID, err)
	}
	return nil
}

// MarkPaymentFailed records a failed attempt; status remains 'scheduled' for retry.
func (r *pgxCashbackRepository) MarkPaymentFailed(ctx context.Context, tx pgx.Tx, paymentID int64, errMsg string) error {
	_, err := tx.Exec(ctx,
		`UPDATE cashback_schema.payments
		 SET last_error=$1, last_attempt_at=now(), attempt_count=attempt_count+1
		 WHERE id=$2`,
		errMsg, paymentID,
	)
	if err != nil {
		return fmt.Errorf("cashback: MarkPaymentFailed id=%d: %w", paymentID, err)
	}
	return nil
}

// UpdateLastDistributedPeriod stamps the plan's last_distributed_period after a successful payment.
func (r *pgxCashbackRepository) UpdateLastDistributedPeriod(ctx context.Context, tx pgx.Tx, planID int64, period int) error {
	_, err := tx.Exec(ctx,
		`UPDATE cashback_schema.plans SET last_distributed_period=$1, updated_at=now() WHERE id=$2`,
		period, planID,
	)
	if err != nil {
		return fmt.Errorf("cashback: UpdateLastDistributedPeriod plan=%d period=%d: %w", planID, period, err)
	}
	return nil
}


// ListPlansByUserID returns up to limit plans for userID, ordered by id DESC.
// Pass beforeID > 0 to cursor-paginate. Pass non-nil status to filter by status.
func (r *pgxCashbackRepository) ListPlansByUserID(ctx context.Context, userID int64, limit int, beforeID int64, status *PlanStatus) ([]Plan, error) {
	var statusVal *string
	if status != nil {
		s := string(*status)
		statusVal = &s
	}
	rows, err := r.pool.Query(ctx,
		`SELECT id, order_id, user_id, monthly_amount_minor, currency,
		        reference_interest_rate_bps, start_date, status,
		        delivered_at, market, commission_snapshot, idempotency_key,
		        product_id, product_title, product_image_url,
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
		return nil, fmt.Errorf("cashback: ListPlansByUserID user=%d: %w", userID, err)
	}
	defer rows.Close()
	var plans []Plan
	for rows.Next() {
		var p Plan
		var statusStr string
		var snapshot []byte
		var productID *int64
		var productTitle, productImageURL *string
		if err := rows.Scan(
			&p.ID, &p.OrderID, &p.UserID, &p.MonthlyAmountMinor, &p.Currency,
			&p.ReferenceInterestRateBps, &p.StartDate, &statusStr,
			&p.DeliveredAt, &p.Market, &snapshot, &p.IdempotencyKey,
			&productID, &productTitle, &productImageURL,
			&p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("cashback: ListPlansByUserID scan: %w", err)
		}
		p.Status = PlanStatus(statusStr)
		p.CommissionSnapshot = snapshot
		if productID != nil {
			p.ProductID = *productID
		}
		if productTitle != nil {
			p.ProductTitle = *productTitle
		}
		if productImageURL != nil {
			p.ProductImageURL = *productImageURL
		}
		plans = append(plans, p)
	}
	return plans, rows.Err()
}

// GetPlanByIDAndUserID fetches a plan by primary key, scoped to userID for IDOR prevention.
// Returns ErrPlanNotFound when no row matches — callers must return 404, NOT 403.
func (r *pgxCashbackRepository) GetPlanByIDAndUserID(ctx context.Context, planID, userID int64) (Plan, error) {
	const q = `
		SELECT id, order_id, user_id, monthly_amount_minor, currency,
		       reference_interest_rate_bps, start_date, status,
		       delivered_at, market, commission_snapshot, idempotency_key,
		       product_id, product_title, product_image_url,
		       created_at, updated_at
		FROM cashback_schema.plans
		WHERE id = $1 AND user_id = $2`

	var p Plan
	var statusStr string
	var snapshot []byte
	var productID *int64
	var productTitle, productImageURL *string
	err := r.pool.QueryRow(ctx, q, planID, userID).Scan(
		&p.ID, &p.OrderID, &p.UserID, &p.MonthlyAmountMinor, &p.Currency,
		&p.ReferenceInterestRateBps, &p.StartDate, &statusStr,
		&p.DeliveredAt, &p.Market, &snapshot, &p.IdempotencyKey,
		&productID, &productTitle, &productImageURL,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Plan{}, ErrPlanNotFound
		}
		return Plan{}, fmt.Errorf("cashback: GetPlanByIDAndUserID plan=%d user=%d: %w", planID, userID, err)
	}
	p.Status = PlanStatus(statusStr)
	p.CommissionSnapshot = snapshot
	if productID != nil {
		p.ProductID = *productID
	}
	if productTitle != nil {
		p.ProductTitle = *productTitle
	}
	if productImageURL != nil {
		p.ProductImageURL = *productImageURL
	}
	return p, nil
}

// ListPaymentsByPlanID returns up to limit payments for planID, ordered by id DESC.
// Pass beforeID > 0 to cursor-paginate.
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
