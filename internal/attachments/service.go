package attachments

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/storage"
)

type service struct {
	repo  Repository
	store storage.PhotoStorage
}

// NewService builds the media service over a repo + object storage.
func NewService(repo Repository, store storage.PhotoStorage) Service {
	return &service{repo: repo, store: store}
}

func (s *service) Upload(ctx context.Context, in UploadInput) (PhotoAttachment, error) {
	if in.EntityType != EntityReview && in.EntityType != EntityReturnItem {
		return PhotoAttachment{}, ErrInvalidEntity
	}
	key := fmt.Sprintf("%s/%d/%s.%s", in.EntityType, in.UserID, uuid.NewString(), in.Ext)
	if err := s.store.Put(ctx, key, in.ContentType, in.Reader, int64(in.ByteSize)); err != nil {
		return PhotoAttachment{}, fmt.Errorf("media: store put: %w", err)
	}
	a, err := s.repo.InsertOrphan(ctx, PhotoAttachment{
		StorageKey:       key,
		ContentType:      in.ContentType,
		ByteSize:         in.ByteSize,
		WidthPx:          in.WidthPx,
		HeightPx:         in.HeightPx,
		UploadedByUserID: in.UserID,
		EntityType:       in.EntityType,
	})
	if err != nil {
		// Best-effort cleanup of the stored object on metadata failure.
		_ = s.store.Delete(ctx, key)
		return PhotoAttachment{}, err
	}
	a.PublicURL = s.store.PublicURL(a.StorageKey)
	return a, nil
}

func (s *service) AttachInTx(ctx context.Context, tx pgx.Tx, entityType string, entityID int64, photoIDs []int64, userID int64) error {
	if len(photoIDs) == 0 {
		return nil
	}
	existing, err := s.repo.CountForEntity(ctx, tx, entityType, entityID)
	if err != nil {
		return err
	}
	if existing+len(photoIDs) > MaxPhotosFor(entityType) {
		return ErrLimitExceeded
	}
	for i, pid := range photoIDs {
		ok, err := s.repo.AttachOrphan(ctx, tx, pid, entityID, userID, entityType, existing+i)
		if err != nil {
			return err
		}
		if !ok {
			return ErrNotOwned // not the uploader's, wrong type, or already attached
		}
	}
	return nil
}

func (s *service) ListByEntity(ctx context.Context, entityType string, entityID int64) ([]PhotoAttachment, error) {
	items, err := s.repo.ListByEntity(ctx, entityType, entityID)
	if err != nil {
		return nil, err
	}
	for i := range items {
		items[i].PublicURL = s.store.PublicURL(items[i].StorageKey)
	}
	return items, nil
}
