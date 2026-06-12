package order

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxCheckoutSessionRepository struct {
	pool *pgxpool.Pool
}

// NewCheckoutSessionRepository returns a CheckoutSessionRepository backed by pgx.
func NewCheckoutSessionRepository(pool *pgxpool.Pool) CheckoutSessionRepository {
	return &pgxCheckoutSessionRepository{pool: pool}
}

func (r *pgxCheckoutSessionRepository) InsertCheckoutSession(ctx context.Context, tx pgx.Tx, s CheckoutSession) (CheckoutSession, error) {
	// Installments defaults to 1 (single charge) when the caller leaves it unset.
	if s.Installments == 0 {
		s.Installments = 1
	}
	err := tx.QueryRow(ctx, `
		INSERT INTO order_schema.checkout_sessions
		    (id, user_id, reservation_id, status, order_ids, amount_minor, currency,
		     provider_ref, installments, expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		RETURNING created_at, updated_at`,
		s.ID, s.UserID, s.ReservationID, string(s.Status),
		s.OrderIDs, s.AmountMinor, s.Currency,
		s.ProviderRef, s.Installments, s.ExpiresAt,
	).Scan(&s.CreatedAt, &s.UpdatedAt)
	if err != nil {
		return CheckoutSession{}, fmt.Errorf("order.checkout_repo: InsertCheckoutSession: %w", err)
	}
	return s, nil
}

func (r *pgxCheckoutSessionRepository) FindCheckoutSessionByID(ctx context.Context, id string) (CheckoutSession, error) {
	var s CheckoutSession
	var status string
	err := r.pool.QueryRow(ctx, `
		SELECT id, user_id, reservation_id, status, order_ids,
		       amount_minor, currency, provider_ref, installments,
		       expires_at, created_at, updated_at
		FROM order_schema.checkout_sessions WHERE id = $1`, id,
	).Scan(
		&s.ID, &s.UserID, &s.ReservationID, &status, &s.OrderIDs,
		&s.AmountMinor, &s.Currency, &s.ProviderRef, &s.Installments,
		&s.ExpiresAt, &s.CreatedAt, &s.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return CheckoutSession{}, ErrCheckoutSessionNotFound
		}
		return CheckoutSession{}, fmt.Errorf("order.checkout_repo: FindCheckoutSessionByID: %w", err)
	}
	s.Status = CheckoutSessionStatus(status)
	return s, nil
}

func (r *pgxCheckoutSessionRepository) UpdateCheckoutSession(ctx context.Context, id string, status CheckoutSessionStatus, providerRef string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE order_schema.checkout_sessions
		SET status = $1, provider_ref = CASE WHEN $2 = '' THEN provider_ref ELSE $2 END,
		    updated_at = $3
		WHERE id = $4`,
		string(status), providerRef, time.Now().UTC(), id,
	)
	if err != nil {
		return fmt.Errorf("order.checkout_repo: UpdateCheckoutSession: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrCheckoutSessionNotFound
	}
	return nil
}
