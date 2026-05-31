package analytics

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a Repository backed by a pgx pool (postgres-ecom).
func NewRepository(pool *pgxpool.Pool) Repository { return &pgxRepository{pool: pool} }

func (r *pgxRepository) InsertEvents(ctx context.Context, batchID uuid.UUID, events []StoredEvent) error {
	if len(events) == 0 {
		return nil
	}
	batch := &pgx.Batch{}
	for _, e := range events {
		raw, err := json.Marshal(e.Payload)
		if err != nil {
			return fmt.Errorf("analytics.repo: marshal payload: %w", err)
		}
		if e.Payload == nil {
			raw = []byte(`{}`)
		}
		batch.Queue(
			`INSERT INTO analytics_schema.analytics_events
			   (session_id, user_id, event_type, payload, client_ts, ingest_batch_id)
			 VALUES ($1, $2, $3, $4::jsonb, $5, $6)`,
			e.SessionID, e.UserID, e.Type, raw, e.ClientTs, batchID,
		)
	}
	br := r.pool.SendBatch(ctx, batch)
	defer br.Close() //nolint:errcheck
	for range events {
		if _, err := br.Exec(); err != nil {
			return fmt.Errorf("analytics.repo: insert event: %w", err)
		}
	}
	return nil
}

func (r *pgxRepository) UpsertRecentlyViewed(ctx context.Context, userID, productID int64, viewedAt time.Time) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO analytics_schema.user_recently_viewed (user_id, product_id, last_viewed_at, view_count)
		 VALUES ($1, $2, $3, 1)
		 ON CONFLICT (user_id, product_id) DO UPDATE
		   SET last_viewed_at = GREATEST(analytics_schema.user_recently_viewed.last_viewed_at, EXCLUDED.last_viewed_at),
		       view_count = analytics_schema.user_recently_viewed.view_count + 1`,
		userID, productID, viewedAt,
	)
	return err
}

func (r *pgxRepository) ResolveUserID(ctx context.Context, sessionID string) (int64, bool, error) {
	var uid int64
	err := r.pool.QueryRow(ctx,
		`SELECT user_id FROM analytics_schema.session_identity WHERE session_id = $1`,
		sessionID,
	).Scan(&uid)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	return uid, true, nil
}

func (r *pgxRepository) InsertSessionIdentity(ctx context.Context, sessionID string, userID int64) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO analytics_schema.session_identity (session_id, user_id)
		 VALUES ($1, $2) ON CONFLICT (session_id) DO NOTHING`,
		sessionID, userID,
	)
	return err
}

func (r *pgxRepository) BackfillRecentlyViewed(ctx context.Context, sessionID string, userID int64) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO analytics_schema.user_recently_viewed (user_id, product_id, last_viewed_at, view_count)
		 SELECT $1,
		        (payload->>'productId')::numeric::bigint,
		        MAX(client_ts),
		        COUNT(*)
		   FROM analytics_schema.analytics_events
		  WHERE session_id = $2
		    AND event_type = 'product_view'
		    AND payload ? 'productId'
		  GROUP BY (payload->>'productId')::numeric::bigint
		 ON CONFLICT (user_id, product_id) DO UPDATE
		   SET last_viewed_at = GREATEST(analytics_schema.user_recently_viewed.last_viewed_at, EXCLUDED.last_viewed_at),
		       view_count = analytics_schema.user_recently_viewed.view_count + EXCLUDED.view_count`,
		userID, sessionID,
	)
	return err
}

func (r *pgxRepository) GetConsent(ctx context.Context, userID int64) (Consent, bool, error) {
	var c Consent
	c.UserID = userID
	err := r.pool.QueryRow(ctx,
		`SELECT analytics_enabled, consented_at, revoked_at
		   FROM analytics_schema.user_consent WHERE user_id = $1`,
		userID,
	).Scan(&c.AnalyticsEnabled, &c.ConsentedAt, &c.RevokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Consent{UserID: userID}, false, nil
	}
	if err != nil {
		return Consent{}, false, err
	}
	return c, true, nil
}

func (r *pgxRepository) UpsertConsent(ctx context.Context, userID int64, enabled bool) (Consent, error) {
	// On enable: consented_at=now(), revoked_at=NULL. On disable: the inverse.
	var c Consent
	c.UserID = userID
	err := r.pool.QueryRow(ctx,
		`INSERT INTO analytics_schema.user_consent (user_id, analytics_enabled, consented_at, revoked_at, updated_at)
		 VALUES ($1, $2,
		         CASE WHEN $2 THEN now() ELSE NULL END,
		         CASE WHEN $2 THEN NULL ELSE now() END,
		         now())
		 ON CONFLICT (user_id) DO UPDATE
		   SET analytics_enabled = EXCLUDED.analytics_enabled,
		       consented_at = CASE WHEN EXCLUDED.analytics_enabled THEN now() ELSE NULL END,
		       revoked_at   = CASE WHEN EXCLUDED.analytics_enabled THEN NULL ELSE now() END,
		       updated_at   = now()
		 RETURNING analytics_enabled, consented_at, revoked_at`,
		userID, enabled,
	).Scan(&c.AnalyticsEnabled, &c.ConsentedAt, &c.RevokedAt)
	if err != nil {
		return Consent{}, err
	}
	return c, nil
}

func (r *pgxRepository) DeleteUserData(ctx context.Context, userID int64) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("analytics.repo: begin erase tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	for _, q := range []string{
		`DELETE FROM analytics_schema.user_recently_viewed WHERE user_id = $1`,
		`DELETE FROM analytics_schema.session_identity WHERE user_id = $1`,
		`DELETE FROM analytics_schema.analytics_events WHERE user_id = $1`,
	} {
		if _, err := tx.Exec(ctx, q, userID); err != nil {
			return fmt.Errorf("analytics.repo: erase: %w", err)
		}
	}
	return tx.Commit(ctx)
}

func (r *pgxRepository) ListRecentlyViewed(ctx context.Context, userID int64, limit int) ([]RecentlyViewedItem, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT product_id, last_viewed_at, view_count
		   FROM analytics_schema.user_recently_viewed
		  WHERE user_id = $1
		  ORDER BY last_viewed_at DESC
		  LIMIT $2`,
		userID, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []RecentlyViewedItem
	for rows.Next() {
		var it RecentlyViewedItem
		if err := rows.Scan(&it.ProductID, &it.LastViewedAt, &it.ViewCount); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (r *pgxRepository) PruneEvents(ctx context.Context, before time.Time, capPerRun int) (int64, error) {
	var total int64
	for {
		tag, err := r.pool.Exec(ctx,
			`DELETE FROM analytics_schema.analytics_events
			  WHERE id IN (
			    SELECT id FROM analytics_schema.analytics_events
			     WHERE server_ts < $1 ORDER BY id LIMIT $2
			  )`,
			before, capPerRun,
		)
		if err != nil {
			return total, err
		}
		n := tag.RowsAffected()
		total += n
		if n < int64(capPerRun) {
			break
		}
	}
	return total, nil
}

func (r *pgxRepository) RebuildRecentlyViewed(ctx context.Context, since time.Time) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO analytics_schema.user_recently_viewed (user_id, product_id, last_viewed_at, view_count)
		 SELECT user_id,
		        (payload->>'productId')::numeric::bigint,
		        MAX(client_ts),
		        COUNT(*)
		   FROM analytics_schema.analytics_events
		  WHERE event_type = 'product_view'
		    AND user_id IS NOT NULL
		    AND server_ts >= $1
		    AND payload ? 'productId'
		  GROUP BY user_id, (payload->>'productId')::numeric::bigint
		 ON CONFLICT (user_id, product_id) DO UPDATE
		   SET last_viewed_at = EXCLUDED.last_viewed_at,
		       view_count = EXCLUDED.view_count`,
		since,
	)
	return err
}
