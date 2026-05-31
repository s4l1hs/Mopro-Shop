//go:build integration

package analytics_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/analytics"
)

const defaultDSN = "postgres://ecom_admin:test123@localhost:6433/mopro_ecom"

const sessA = "aaaaaaaa-1111-2222-3333-444444444444"

var pool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("ANALYTICS_TEST_DSN")
	if dsn == "" {
		dsn = defaultDSN
	}
	ctx := context.Background()
	var err error
	pool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "analytics integration: pool: %v\n", err)
		os.Exit(1)
	}
	if err := pool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "analytics integration: ping: %v\n", err)
		os.Exit(1)
	}
	// Run each statement individually (the test pool uses the extended protocol,
	// so a multi-statement Exec would run only the first).
	stmts := []string{
		`CREATE SCHEMA IF NOT EXISTS analytics_schema`,
		`DROP TABLE IF EXISTS analytics_schema.analytics_events CASCADE`,
		`DROP TABLE IF EXISTS analytics_schema.session_identity CASCADE`,
		`DROP TABLE IF EXISTS analytics_schema.user_consent CASCADE`,
		`DROP TABLE IF EXISTS analytics_schema.user_recently_viewed CASCADE`,
		`CREATE TABLE analytics_schema.analytics_events (
		   id BIGSERIAL PRIMARY KEY, session_id TEXT NOT NULL, user_id BIGINT,
		   event_type TEXT NOT NULL, payload JSONB NOT NULL DEFAULT '{}'::jsonb,
		   client_ts TIMESTAMPTZ NOT NULL, server_ts TIMESTAMPTZ NOT NULL DEFAULT now(),
		   ingest_batch_id UUID)`,
		`CREATE TABLE analytics_schema.session_identity (
		   session_id TEXT PRIMARY KEY, user_id BIGINT NOT NULL,
		   resolved_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE analytics_schema.user_consent (
		   user_id BIGINT PRIMARY KEY, analytics_enabled BOOLEAN NOT NULL DEFAULT false,
		   consented_at TIMESTAMPTZ, revoked_at TIMESTAMPTZ, updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE analytics_schema.user_recently_viewed (
		   user_id BIGINT NOT NULL, product_id BIGINT NOT NULL,
		   last_viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(), view_count INTEGER NOT NULL DEFAULT 1,
		   PRIMARY KEY (user_id, product_id))`,
	}
	for _, s := range stmts {
		if _, err := pool.Exec(ctx, s); err != nil {
			fmt.Fprintf(os.Stderr, "analytics integration: ddl %q: %v\n", s[:30], err)
			os.Exit(1)
		}
	}
	code := m.Run()
	pool.Close()
	os.Exit(code)
}

func newSvc() analytics.Service { return analytics.NewService(analytics.NewRepository(pool)) }

func pv(productID int) analytics.Event {
	return analytics.Event{
		Type:     analytics.EventProductView,
		Payload:  map[string]any{"productId": float64(productID)},
		ClientTs: time.Now().UTC(),
	}
}

func u(i int64) *int64 { return &i }

func TestIntegration_IngestStoresAndProjects(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	const uid = 1001
	if _, err := svc.SetConsent(ctx, uid, true); err != nil {
		t.Fatal(err)
	}
	if err := svc.Ingest(ctx, analytics.IngestBatch{
		SessionID: sessA, UserID: u(uid), Events: []analytics.Event{pv(50), pv(50), pv(51)},
	}); err != nil {
		t.Fatal(err)
	}
	items, err := svc.RecentlyViewed(ctx, uid, 20)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Fatalf("want 2 distinct products, got %d", len(items))
	}
	for _, it := range items {
		if it.ProductID == 50 && it.ViewCount != 2 {
			t.Fatalf("product 50 view_count want 2, got %d", it.ViewCount)
		}
	}
}

func TestIntegration_ConsentGateBlocks(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	const uid = 1002
	if _, err := svc.SetConsent(ctx, uid, false); err != nil {
		t.Fatal(err)
	}
	if err := svc.Ingest(ctx, analytics.IngestBatch{
		SessionID: "bbbbbbbb-1111-2222-3333-444444444444", UserID: u(uid), Events: []analytics.Event{pv(99)},
	}); err != nil {
		t.Fatal(err)
	}
	items, _ := svc.RecentlyViewed(ctx, uid, 20)
	if len(items) != 0 {
		t.Fatalf("consent-off must store nothing, got %d projection rows", len(items))
	}
}

func TestIntegration_IdentifyBackfill(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	const uid = 1003
	const sess = "cccccccc-1111-2222-3333-444444444444"
	// Guest events (no UserID) are stored even without consent (client-side gate).
	if err := svc.Ingest(ctx, analytics.IngestBatch{
		SessionID: sess, Events: []analytics.Event{pv(70), pv(71), pv(70)},
	}); err != nil {
		t.Fatal(err)
	}
	// Before identify the user has no projection.
	if items, _ := svc.RecentlyViewed(ctx, uid, 20); len(items) != 0 {
		t.Fatalf("pre-identify projection should be empty, got %d", len(items))
	}
	if err := svc.IdentifySession(ctx, sess, uid); err != nil {
		t.Fatal(err)
	}
	items, _ := svc.RecentlyViewed(ctx, uid, 20)
	if len(items) != 2 {
		t.Fatalf("backfill should produce 2 products, got %d", len(items))
	}
}

func TestIntegration_RecentlyViewedOrderAndLimit(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	const uid = 1004
	_, _ = svc.SetConsent(ctx, uid, true)
	base := time.Now().UTC()
	for i, pid := range []int{80, 81, 82} {
		_ = svc.Ingest(ctx, analytics.IngestBatch{
			SessionID: sessA, UserID: u(uid),
			Events: []analytics.Event{{
				Type: analytics.EventProductView, Payload: map[string]any{"productId": float64(pid)},
				ClientTs: base.Add(time.Duration(i) * time.Minute),
			}},
		})
	}
	items, _ := svc.RecentlyViewed(ctx, uid, 2)
	if len(items) != 2 {
		t.Fatalf("limit should clamp to 2, got %d", len(items))
	}
	if items[0].ProductID != 82 {
		t.Fatalf("most recent (82) should be first, got %d", items[0].ProductID)
	}
}

func TestIntegration_Prune(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	// Insert one ancient + one fresh event directly.
	_, err := pool.Exec(ctx,
		`INSERT INTO analytics_schema.analytics_events (session_id, event_type, payload, client_ts, server_ts)
		 VALUES ('dddddddd-1111-2222-3333-444444444444','page_view','{"path":"/"}', now(), now() - interval '200 days'),
		        ('dddddddd-1111-2222-3333-444444444444','page_view','{"path":"/x"}', now(), now())`)
	if err != nil {
		t.Fatal(err)
	}
	n, err := svc.PruneEvents(ctx, time.Now().Add(-90*24*time.Hour), 100)
	if err != nil {
		t.Fatal(err)
	}
	if n < 1 {
		t.Fatalf("prune should delete the 200-day-old event, deleted %d", n)
	}
	var remaining int
	_ = pool.QueryRow(ctx,
		`SELECT count(*) FROM analytics_schema.analytics_events
		   WHERE session_id='dddddddd-1111-2222-3333-444444444444'`).Scan(&remaining)
	if remaining != 1 {
		t.Fatalf("fresh event should survive prune, remaining=%d", remaining)
	}
}

func TestIntegration_EraseUserData(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	const uid = 1005
	const sess = "eeeeeeee-1111-2222-3333-444444444444"
	_, _ = svc.SetConsent(ctx, uid, true)
	_ = svc.Ingest(ctx, analytics.IngestBatch{SessionID: sess, UserID: u(uid), Events: []analytics.Event{pv(60)}})
	_ = svc.IdentifySession(ctx, sess, uid)

	if err := svc.DeleteUserData(ctx, uid); err != nil {
		t.Fatal(err)
	}
	if items, _ := svc.RecentlyViewed(ctx, uid, 20); len(items) != 0 {
		t.Fatalf("erase should clear recently-viewed, got %d", len(items))
	}
	var evCount, idCount int
	_ = pool.QueryRow(ctx, `SELECT count(*) FROM analytics_schema.analytics_events WHERE user_id=$1`, uid).Scan(&evCount)
	_ = pool.QueryRow(ctx, `SELECT count(*) FROM analytics_schema.session_identity WHERE user_id=$1`, uid).Scan(&idCount)
	if evCount != 0 || idCount != 0 {
		t.Fatalf("erase should clear events+identity, got events=%d identity=%d", evCount, idCount)
	}
}
