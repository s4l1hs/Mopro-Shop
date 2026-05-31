package inbox

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

const maxPageSize = 50

type service struct {
	repo Repository
}

// NewService builds the inbox Service.
func NewService(repo Repository) Service { return &service{repo: repo} }

func (s *service) List(ctx context.Context, userID int64, unreadOnly bool, page, pageSize int) ([]Notification, int, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > maxPageSize {
		pageSize = 20
	}
	items, err := s.repo.List(ctx, userID, unreadOnly, pageSize, (page-1)*pageSize)
	if err != nil {
		return nil, 0, err
	}
	total, err := s.repo.Count(ctx, userID, unreadOnly)
	if err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func (s *service) UnreadCount(ctx context.Context, userID int64) (int, error) {
	return s.repo.Count(ctx, userID, true)
}

// MarkRead is idempotent: marking an already-read (or absent) notification is a
// no-op success. Ownership is enforced by the repo's WHERE user_id clause.
func (s *service) MarkRead(ctx context.Context, userID, id int64) error {
	return s.repo.MarkRead(ctx, userID, id)
}

func (s *service) MarkAllRead(ctx context.Context, userID int64) (int, error) {
	return s.repo.MarkAllRead(ctx, userID)
}

// GetPreferences merges stored rows over the default matrix so the client always
// receives the full category×channel grid.
func (s *service) GetPreferences(ctx context.Context, userID int64) ([]Preference, error) {
	stored, err := s.repo.ListPreferences(ctx, userID)
	if err != nil {
		return nil, err
	}
	override := make(map[string]bool, len(stored))
	for _, p := range stored {
		override[p.Category+"\x00"+p.Channel] = p.Enabled
	}
	out := DefaultPreferences()
	for i := range out {
		if v, ok := override[out[i].Category+"\x00"+out[i].Channel]; ok {
			out[i].Enabled = v
		}
	}
	return out, nil
}

// UpsertPreferences validates category/channel and upserts each row in one tx.
// Partial submits only touch the rows provided (others keep their stored value).
func (s *service) UpsertPreferences(ctx context.Context, userID int64, prefs []Preference) error {
	valid := map[string]bool{}
	for _, c := range PrefCategories {
		valid[c] = true
	}
	validCh := map[string]bool{ChannelInApp: true, ChannelEmail: true, ChannelPush: true}
	for _, p := range prefs {
		if !valid[p.Category] || !validCh[p.Channel] {
			return fmt.Errorf("%w: %s/%s", ErrInvalidPreference, p.Category, p.Channel)
		}
	}
	return s.repo.WithTx(ctx, func(tx pgx.Tx) error {
		return s.repo.UpsertPreferences(ctx, tx, userID, prefs)
	})
}

func (s *service) RegisterPushToken(ctx context.Context, userID int64, token, platform string) error {
	switch platform {
	case "web", "android", "ios":
	default:
		return fmt.Errorf("%w: %s", ErrInvalidPlatform, platform)
	}
	if token == "" {
		return ErrInvalidPushToken
	}
	return s.repo.UpsertPushToken(ctx, userID, token, platform)
}

func (s *service) DeletePushToken(ctx context.Context, userID int64, token string) error {
	if token == "" {
		return ErrInvalidPushToken
	}
	return s.repo.DeletePushToken(ctx, userID, token)
}
