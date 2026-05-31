//go:build integration

package inbox_test

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/inbox"
)

const defaultDSN = "postgres://ecom_admin:test123@localhost:6433/mopro_ecom"

var pool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("INBOX_TEST_DSN")
	if dsn == "" {
		dsn = defaultDSN
	}
	ctx := context.Background()
	var err error
	pool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "inbox integration: pool: %v\n", err)
		os.Exit(1)
	}
	if err := pool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "inbox integration: ping: %v\n", err)
		os.Exit(1)
	}
	ddl := `
CREATE SCHEMA IF NOT EXISTS inbox_schema;
DROP TABLE IF EXISTS inbox_schema.notifications CASCADE;
DROP TABLE IF EXISTS inbox_schema.notification_preferences CASCADE;
DROP TABLE IF EXISTS inbox_schema.push_tokens CASCADE;
CREATE TABLE inbox_schema.notifications (
  id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL, type TEXT NOT NULL,
  title_key TEXT NOT NULL, body_key TEXT NOT NULL, body_params JSONB NOT NULL DEFAULT '{}'::jsonb,
  deep_link TEXT, is_read BOOLEAN NOT NULL DEFAULT false, read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), expires_at TIMESTAMPTZ);
CREATE TABLE inbox_schema.notification_preferences (
  user_id BIGINT NOT NULL, category TEXT NOT NULL, channel TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT true, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, category, channel));
CREATE TABLE inbox_schema.push_tokens (
  id BIGSERIAL PRIMARY KEY, user_id BIGINT NOT NULL, token TEXT NOT NULL, platform TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT push_tokens_token_uq UNIQUE (token));`
	if _, err := pool.Exec(ctx, ddl); err != nil {
		fmt.Fprintf(os.Stderr, "inbox integration: ddl: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	pool.Close()
	os.Exit(code)
}

func TestIntegration_InboxLifecycle(t *testing.T) {
	ctx := context.Background()
	repo := inbox.NewRepository(pool)
	svc := inbox.NewService(repo)
	const uid = 7001

	// Seed 3 notifications.
	for i := 0; i < 3; i++ {
		if _, err := repo.Insert(ctx, inbox.Notification{
			UserID: uid, Type: inbox.TypeOrderStatus,
			TitleKey: "notifications.order_title", BodyKey: "notifications.order_body",
			BodyParams: map[string]string{"id": fmt.Sprintf("%d", i)},
		}); err != nil {
			t.Fatal(err)
		}
	}

	if n, _ := svc.UnreadCount(ctx, uid); n != 3 {
		t.Fatalf("unread=%d want 3", n)
	}

	items, total, err := svc.List(ctx, uid, true, 1, 20)
	if err != nil || total != 3 || len(items) != 3 {
		t.Fatalf("list unread: total=%d items=%d err=%v", total, len(items), err)
	}

	// Mark one read (idempotent).
	if err := svc.MarkRead(ctx, uid, items[0].ID); err != nil {
		t.Fatal(err)
	}
	if err := svc.MarkRead(ctx, uid, items[0].ID); err != nil {
		t.Fatalf("re-mark must be no-op, got %v", err)
	}
	if n, _ := svc.UnreadCount(ctx, uid); n != 2 {
		t.Fatalf("unread after mark=%d want 2", n)
	}

	// Mark-all-read flips the remaining 2.
	marked, err := svc.MarkAllRead(ctx, uid)
	if err != nil || marked != 2 {
		t.Fatalf("markAllRead=%d want 2 (err %v)", marked, err)
	}
	if n, _ := svc.UnreadCount(ctx, uid); n != 0 {
		t.Fatalf("unread after all=%d want 0", n)
	}

	// Preferences: defaults then override persists.
	if err := svc.UpsertPreferences(ctx, uid, []inbox.Preference{
		{Category: inbox.TypeMarketing, Channel: inbox.ChannelEmail, Enabled: true},
	}); err != nil {
		t.Fatal(err)
	}
	prefs, _ := svc.GetPreferences(ctx, uid)
	for _, p := range prefs {
		if p.Category == inbox.TypeMarketing && p.Channel == inbox.ChannelEmail && !p.Enabled {
			t.Error("marketing/email override did not persist")
		}
	}

	// Push token upsert: same token re-registered updates, stays one row.
	if err := svc.RegisterPushToken(ctx, uid, "tok-A", "web"); err != nil {
		t.Fatal(err)
	}
	if err := svc.RegisterPushToken(ctx, uid, "tok-A", "android"); err != nil {
		t.Fatal(err)
	}
	var rows int
	if err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM inbox_schema.push_tokens WHERE token='tok-A'`).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Errorf("push token rows=%d want 1 (upsert)", rows)
	}
}
