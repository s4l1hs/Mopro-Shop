package support

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a support Repository backed by a pgx pool.
func NewRepository(pool *pgxpool.Pool) Repository { return &pgxRepository{pool: pool} }

func nullableInt64(v int64) any {
	if v == 0 {
		return nil
	}
	return v
}

func (r *pgxRepository) Insert(ctx context.Context, in TicketInput) (Ticket, error) {
	t := Ticket{
		UserID: in.UserID, Email: in.Email, Subject: in.Subject, Body: in.Body,
		Category: in.Category, RelatedOrderID: in.RelatedOrderID,
		RelatedArticleSlug: in.RelatedArticleSlug, Status: "open",
	}
	err := r.pool.QueryRow(ctx,
		`INSERT INTO support_schema.support_tickets
		   (user_id, email, subject, body, category, related_order_id, related_article_slug)
		 VALUES ($1,$2,$3,$4,$5,$6,$7)
		 RETURNING id, status, created_at`,
		nullableInt64(in.UserID), in.Email, in.Subject, in.Body, in.Category,
		nullableInt64(in.RelatedOrderID), nullText(in.RelatedArticleSlug)).
		Scan(&t.ID, &t.Status, &t.CreatedAt)
	if err != nil {
		return Ticket{}, fmt.Errorf("support.repo: insert: %w", err)
	}
	return t, nil
}

func (r *pgxRepository) ListByUser(ctx context.Context, userID int64, limit, offset int) ([]Ticket, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, COALESCE(user_id,0), email, subject, body, category,
		        COALESCE(related_order_id,0), COALESCE(related_article_slug,''),
		        status, created_at
		   FROM support_schema.support_tickets
		  WHERE user_id = $1
		  ORDER BY created_at DESC, id DESC
		  LIMIT $2 OFFSET $3`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("support.repo: list: %w", err)
	}
	defer rows.Close()
	return scanTickets(rows)
}

func (r *pgxRepository) GetByID(ctx context.Context, id int64) (Ticket, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, COALESCE(user_id,0), email, subject, body, category,
		        COALESCE(related_order_id,0), COALESCE(related_article_slug,''),
		        status, created_at
		   FROM support_schema.support_tickets WHERE id = $1`, id)
	if err != nil {
		return Ticket{}, fmt.Errorf("support.repo: get: %w", err)
	}
	defer rows.Close()
	out, err := scanTickets(rows)
	if err != nil {
		return Ticket{}, err
	}
	if len(out) == 0 {
		return Ticket{}, ErrTicketNotFound
	}
	return out[0], nil
}

func scanTickets(rows pgx.Rows) ([]Ticket, error) {
	var out []Ticket
	for rows.Next() {
		var t Ticket
		if err := rows.Scan(&t.ID, &t.UserID, &t.Email, &t.Subject, &t.Body, &t.Category,
			&t.RelatedOrderID, &t.RelatedArticleSlug, &t.Status, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("support.repo: scan: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func nullText(s string) any {
	if s == "" {
		return nil
	}
	return s
}
