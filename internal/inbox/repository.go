package inbox

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a Repository backed by a pgx pool.
func NewRepository(pool *pgxpool.Pool) Repository { return &pgxRepository{pool: pool} }

func (r *pgxRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("inbox.repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *pgxRepository) List(ctx context.Context, userID int64, unreadOnly bool, limit, offset int) ([]Notification, error) {
	q := `SELECT id, user_id, type, title_key, body_key, body_params, deep_link,
	             is_read, read_at, created_at, expires_at
	        FROM inbox_schema.notifications
	       WHERE user_id = $1`
	if unreadOnly {
		q += ` AND is_read = false`
	}
	q += ` ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3`
	rows, err := r.pool.Query(ctx, q, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("inbox.repo: list: %w", err)
	}
	defer rows.Close()
	var out []Notification
	for rows.Next() {
		var n Notification
		var params []byte
		if err := rows.Scan(&n.ID, &n.UserID, &n.Type, &n.TitleKey, &n.BodyKey, &params,
			&n.DeepLink, &n.IsRead, &n.ReadAt, &n.CreatedAt, &n.ExpiresAt); err != nil {
			return nil, fmt.Errorf("inbox.repo: scan: %w", err)
		}
		n.BodyParams = map[string]string{}
		if len(params) > 0 {
			_ = json.Unmarshal(params, &n.BodyParams)
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

func (r *pgxRepository) Count(ctx context.Context, userID int64, unreadOnly bool) (int, error) {
	q := `SELECT COUNT(*) FROM inbox_schema.notifications WHERE user_id = $1`
	if unreadOnly {
		q += ` AND is_read = false`
	}
	var n int
	if err := r.pool.QueryRow(ctx, q, userID).Scan(&n); err != nil {
		return 0, fmt.Errorf("inbox.repo: count: %w", err)
	}
	return n, nil
}

func (r *pgxRepository) MarkRead(ctx context.Context, userID, id int64) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE inbox_schema.notifications
		    SET is_read = true, read_at = COALESCE(read_at, now())
		  WHERE id = $1 AND user_id = $2 AND is_read = false`, id, userID)
	if err != nil {
		return fmt.Errorf("inbox.repo: mark read: %w", err)
	}
	return nil
}

func (r *pgxRepository) MarkAllRead(ctx context.Context, userID int64) (int, error) {
	tag, err := r.pool.Exec(ctx,
		`UPDATE inbox_schema.notifications
		    SET is_read = true, read_at = now()
		  WHERE user_id = $1 AND is_read = false`, userID)
	if err != nil {
		return 0, fmt.Errorf("inbox.repo: mark all read: %w", err)
	}
	return int(tag.RowsAffected()), nil
}

func (r *pgxRepository) ListPreferences(ctx context.Context, userID int64) ([]Preference, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT category, channel, enabled FROM inbox_schema.notification_preferences
		  WHERE user_id = $1`, userID)
	if err != nil {
		return nil, fmt.Errorf("inbox.repo: list prefs: %w", err)
	}
	defer rows.Close()
	var out []Preference
	for rows.Next() {
		var p Preference
		if err := rows.Scan(&p.Category, &p.Channel, &p.Enabled); err != nil {
			return nil, fmt.Errorf("inbox.repo: scan pref: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (r *pgxRepository) UpsertPreferences(ctx context.Context, tx pgx.Tx, userID int64, prefs []Preference) error {
	for _, p := range prefs {
		_, err := tx.Exec(ctx,
			`INSERT INTO inbox_schema.notification_preferences (user_id, category, channel, enabled, updated_at)
			 VALUES ($1,$2,$3,$4, now())
			 ON CONFLICT (user_id, category, channel)
			 DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now()`,
			userID, p.Category, p.Channel, p.Enabled)
		if err != nil {
			return fmt.Errorf("inbox.repo: upsert pref: %w", err)
		}
	}
	return nil
}

func (r *pgxRepository) UpsertPushToken(ctx context.Context, userID int64, token, platform string) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO inbox_schema.push_tokens (user_id, token, platform, last_seen)
		 VALUES ($1,$2,$3, now())
		 ON CONFLICT (token)
		 DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, last_seen = now()`,
		userID, token, platform)
	if err != nil {
		return fmt.Errorf("inbox.repo: upsert push token: %w", err)
	}
	return nil
}

func (r *pgxRepository) DeletePushToken(ctx context.Context, userID int64, token string) error {
	_, err := r.pool.Exec(ctx,
		`DELETE FROM inbox_schema.push_tokens WHERE token = $1 AND user_id = $2`, token, userID)
	if err != nil {
		return fmt.Errorf("inbox.repo: delete push token: %w", err)
	}
	return nil
}

func (r *pgxRepository) Insert(ctx context.Context, n Notification) (Notification, error) {
	params := n.BodyParams
	if params == nil {
		params = map[string]string{}
	}
	raw, _ := json.Marshal(params)
	err := r.pool.QueryRow(ctx,
		`INSERT INTO inbox_schema.notifications
		   (user_id, type, title_key, body_key, body_params, deep_link, expires_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7)
		 RETURNING id, created_at, is_read`,
		n.UserID, n.Type, n.TitleKey, n.BodyKey, raw, n.DeepLink, n.ExpiresAt).
		Scan(&n.ID, &n.CreatedAt, &n.IsRead)
	if err != nil {
		return Notification{}, fmt.Errorf("inbox.repo: insert: %w", err)
	}
	return n, nil
}
