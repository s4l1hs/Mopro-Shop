package attachments

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxRepository struct{ pool *pgxpool.Pool }

// NewRepository returns a Repository backed by a pgx pool (postgres-ecom).
func NewRepository(pool *pgxpool.Pool) Repository { return &pgxRepository{pool: pool} }

func (r *pgxRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("media.repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *pgxRepository) InsertOrphan(ctx context.Context, a PhotoAttachment) (PhotoAttachment, error) {
	err := r.pool.QueryRow(ctx,
		`INSERT INTO attachments_schema.photo_attachments
		   (storage_key, content_type, byte_size, width_px, height_px,
		    uploaded_by_user_id, entity_type, entity_id, sort_order)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,NULL,0)
		 RETURNING id, created_at`,
		a.StorageKey, a.ContentType, a.ByteSize, a.WidthPx, a.HeightPx,
		a.UploadedByUserID, a.EntityType).
		Scan(&a.ID, &a.CreatedAt)
	if err != nil {
		return PhotoAttachment{}, fmt.Errorf("media.repo: insert orphan: %w", err)
	}
	return a, nil
}

func (r *pgxRepository) ListByEntity(ctx context.Context, entityType string, entityID int64) ([]PhotoAttachment, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, storage_key, content_type, byte_size,
		        COALESCE(width_px,0), COALESCE(height_px,0), sort_order
		   FROM attachments_schema.photo_attachments
		  WHERE entity_type=$1 AND entity_id=$2
		  ORDER BY sort_order ASC, id ASC`, entityType, entityID)
	if err != nil {
		return nil, fmt.Errorf("media.repo: list by entity: %w", err)
	}
	defer rows.Close()
	out := []PhotoAttachment{}
	for rows.Next() {
		var a PhotoAttachment
		if err := rows.Scan(&a.ID, &a.StorageKey, &a.ContentType, &a.ByteSize,
			&a.WidthPx, &a.HeightPx, &a.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func (r *pgxRepository) CountForEntity(ctx context.Context, tx pgx.Tx, entityType string, entityID int64) (int, error) {
	var n int
	err := tx.QueryRow(ctx,
		`SELECT COUNT(*) FROM attachments_schema.photo_attachments
		  WHERE entity_type=$1 AND entity_id=$2`, entityType, entityID).Scan(&n)
	return n, err
}

// AttachOrphan attaches one owned orphan photo. Returns false (no error) when
// the row didn't match (not owned, wrong entity_type, or already attached).
func (r *pgxRepository) AttachOrphan(ctx context.Context, tx pgx.Tx, photoID, entityID, userID int64, entityType string, sortOrder int) (bool, error) {
	ct, err := tx.Exec(ctx,
		`UPDATE attachments_schema.photo_attachments
		    SET entity_id=$1, sort_order=$2
		  WHERE id=$3 AND uploaded_by_user_id=$4 AND entity_type=$5 AND entity_id IS NULL`,
		entityID, sortOrder, photoID, userID, entityType)
	if err != nil {
		return false, fmt.Errorf("media.repo: attach orphan: %w", err)
	}
	return ct.RowsAffected() == 1, nil
}
