// Package attachments owns media_schema.photo_attachments (core-svc). It is the
// consumer-UGC photo store for reviews + return items (ADR-0004). Distinct from
// the jobs-svc `media` module (product-image resize pipeline).: the orphan-upload +
// two-phase attach lifecycle for review/return photos (ADR-0004). Storage bytes
// live in internal/storage; this module owns the metadata rows.
package attachments

import (
	"context"
	"io"

	"github.com/jackc/pgx/v5"
)

// Service is the media module's public surface.
type Service interface {
	// Upload stores the (already-validated) bytes + inserts an orphan row,
	// returning the persisted attachment (with PublicURL populated).
	Upload(ctx context.Context, in UploadInput) (PhotoAttachment, error)
	// AttachInTx attaches owned orphan photos to an entity inside an existing tx
	// (called from a review/return submission tx). Enforces ownership, orphan
	// state, and the per-entity limit; assigns sort_order by slice index.
	AttachInTx(ctx context.Context, tx pgx.Tx, entityType string, entityID int64, photoIDs []int64, userID int64) error
	// ListByEntity returns an entity's attached photos in display order.
	ListByEntity(ctx context.Context, entityType string, entityID int64) ([]PhotoAttachment, error)
}

// UploadInput carries a validated photo ready to persist.
type UploadInput struct {
	UserID      int64
	EntityType  string
	ContentType string
	Ext         string // file extension without dot (jpg|png|webp)
	ByteSize    int
	WidthPx     int
	HeightPx    int
	Reader      io.Reader
}

// Repository is the media_schema persistence boundary.
type Repository interface {
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
	InsertOrphan(ctx context.Context, a PhotoAttachment) (PhotoAttachment, error)
	ListByEntity(ctx context.Context, entityType string, entityID int64) ([]PhotoAttachment, error)
	CountForEntity(ctx context.Context, tx pgx.Tx, entityType string, entityID int64) (int, error)
	AttachOrphan(ctx context.Context, tx pgx.Tx, photoID, entityID, userID int64, entityType string, sortOrder int) (bool, error)
}
