package order

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxReturnRepository struct {
	pool *pgxpool.Pool
}

// NewReturnRepository returns a ReturnRepository backed by a pgx pool.
func NewReturnRepository(pool *pgxpool.Pool) ReturnRepository {
	return &pgxReturnRepository{pool: pool}
}

func (r *pgxReturnRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("order.returns.repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *pgxReturnRepository) InsertReturn(ctx context.Context, tx pgx.Tx, rec Return) (Return, error) {
	row := tx.QueryRow(ctx,
		`INSERT INTO order_schema.returns
		    (order_id, user_id, status, reason, description, refund_amount_minor, refund_currency)
		 VALUES ($1,$2,$3,$4,$5,$6,$7)
		 RETURNING id, created_at, updated_at`,
		rec.OrderID, rec.UserID, string(rec.Status), string(rec.Reason),
		rec.Description, rec.RefundAmountMinor, rec.RefundCurrency)
	if err := row.Scan(&rec.ID, &rec.CreatedAt, &rec.UpdatedAt); err != nil {
		return Return{}, fmt.Errorf("order.returns.repo: insert return: %w", err)
	}
	return rec, nil
}

func (r *pgxReturnRepository) InsertReturnItem(ctx context.Context, tx pgx.Tx, it ReturnItem) (ReturnItem, error) {
	row := tx.QueryRow(ctx,
		`INSERT INTO order_schema.return_items (return_id, order_id, order_item_id, quantity)
		 VALUES ($1,$2,$3,$4) RETURNING id`,
		it.ReturnID, it.OrderID, it.OrderItemID, it.Quantity)
	if err := row.Scan(&it.ID); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == pgUniqueViolation {
			return ReturnItem{}, ErrReturnAlreadyExists
		}
		return ReturnItem{}, fmt.Errorf("order.returns.repo: insert item: %w", err)
	}
	return it, nil
}

func (r *pgxReturnRepository) InsertReturnStatusHistory(ctx context.Context, tx pgx.Tx, returnID int64, status, note string) error {
	_, err := tx.Exec(ctx,
		`INSERT INTO order_schema.return_status_history (return_id, status, note)
		 VALUES ($1,$2,$3)`, returnID, status, note)
	if err != nil {
		return fmt.Errorf("order.returns.repo: insert history: %w", err)
	}
	return nil
}

func (r *pgxReturnRepository) GetReturn(ctx context.Context, returnID int64) (Return, []ReturnItem, error) {
	var rec Return
	var status, reason string
	err := r.pool.QueryRow(ctx,
		`SELECT id, order_id, user_id, status, reason, description,
		        refund_amount_minor, refund_currency, created_at, updated_at
		   FROM order_schema.returns WHERE id = $1`, returnID).
		Scan(&rec.ID, &rec.OrderID, &rec.UserID, &status, &reason, &rec.Description,
			&rec.RefundAmountMinor, &rec.RefundCurrency, &rec.CreatedAt, &rec.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Return{}, nil, ErrReturnNotFound
		}
		return Return{}, nil, fmt.Errorf("order.returns.repo: get return: %w", err)
	}
	rec.Status = ReturnStatus(status)
	rec.Reason = ReturnReason(reason)

	rows, err := r.pool.Query(ctx,
		`SELECT id, return_id, order_id, order_item_id, quantity
		   FROM order_schema.return_items WHERE return_id = $1 ORDER BY id ASC`, returnID)
	if err != nil {
		return Return{}, nil, fmt.Errorf("order.returns.repo: get items: %w", err)
	}
	defer rows.Close()
	var items []ReturnItem
	for rows.Next() {
		var it ReturnItem
		if err := rows.Scan(&it.ID, &it.ReturnID, &it.OrderID, &it.OrderItemID, &it.Quantity); err != nil {
			return Return{}, nil, fmt.Errorf("order.returns.repo: scan item: %w", err)
		}
		items = append(items, it)
	}
	return rec, items, rows.Err()
}

func (r *pgxReturnRepository) ListReturnsByUser(ctx context.Context, userID int64, limit, offset int) ([]Return, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, order_id, user_id, status, reason, description,
		        refund_amount_minor, refund_currency, created_at, updated_at
		   FROM order_schema.returns
		  WHERE user_id = $1
		  ORDER BY created_at DESC, id DESC
		  LIMIT $2 OFFSET $3`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("order.returns.repo: list: %w", err)
	}
	defer rows.Close()
	var out []Return
	for rows.Next() {
		var rec Return
		var status, reason string
		if err := rows.Scan(&rec.ID, &rec.OrderID, &rec.UserID, &status, &reason, &rec.Description,
			&rec.RefundAmountMinor, &rec.RefundCurrency, &rec.CreatedAt, &rec.UpdatedAt); err != nil {
			return nil, fmt.Errorf("order.returns.repo: scan: %w", err)
		}
		rec.Status = ReturnStatus(status)
		rec.Reason = ReturnReason(reason)
		out = append(out, rec)
	}
	return out, rows.Err()
}

func (r *pgxReturnRepository) ReturnedQtyByOrder(ctx context.Context, orderID int64) (map[int64]int, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT order_item_id, COALESCE(SUM(quantity),0)
		   FROM order_schema.return_items WHERE order_id = $1 GROUP BY order_item_id`, orderID)
	if err != nil {
		return nil, fmt.Errorf("order.returns.repo: returned qty: %w", err)
	}
	defer rows.Close()
	out := make(map[int64]int)
	for rows.Next() {
		var itemID int64
		var qty int
		if err := rows.Scan(&itemID, &qty); err != nil {
			return nil, fmt.Errorf("order.returns.repo: scan qty: %w", err)
		}
		out[itemID] = qty
	}
	return out, rows.Err()
}
