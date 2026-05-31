package inbox

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// Service is the public interface of the inbox module (core-svc).
type Service interface {
	List(ctx context.Context, userID int64, unreadOnly bool, page, pageSize int) ([]Notification, int, error)
	UnreadCount(ctx context.Context, userID int64) (int, error)
	MarkRead(ctx context.Context, userID, id int64) error
	MarkAllRead(ctx context.Context, userID int64) (int, error)
	GetPreferences(ctx context.Context, userID int64) ([]Preference, error)
	UpsertPreferences(ctx context.Context, userID int64, prefs []Preference) error
	RegisterPushToken(ctx context.Context, userID int64, token, platform string) error
	DeletePushToken(ctx context.Context, userID int64, token string) error
}

// Repository is the storage interface used only by service.go.
type Repository interface {
	List(ctx context.Context, userID int64, unreadOnly bool, limit, offset int) ([]Notification, error)
	Count(ctx context.Context, userID int64, unreadOnly bool) (int, error)
	MarkRead(ctx context.Context, userID, id int64) error
	MarkAllRead(ctx context.Context, userID int64) (int, error)
	ListPreferences(ctx context.Context, userID int64) ([]Preference, error)
	UpsertPreferences(ctx context.Context, tx pgx.Tx, userID int64, prefs []Preference) error
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
	UpsertPushToken(ctx context.Context, userID int64, token, platform string) error
	DeletePushToken(ctx context.Context, userID int64, token string) error
	// Insert is used by event consumers / seeding to create a notification.
	Insert(ctx context.Context, n Notification) (Notification, error)
}
