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
		`DROP TABLE IF EXISTS analytics_schema.popular_products CASCADE`,
		`DROP TABLE IF EXISTS analytics_schema.product_co_views CASCADE`,
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
		`CREATE TABLE analytics_schema.popular_products (
		   scope TEXT NOT NULL, product_id BIGINT NOT NULL, view_count INTEGER NOT NULL,
		   refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (scope, product_id))`,
		`CREATE TABLE analytics_schema.product_co_views (
		   product_a BIGINT NOT NULL, product_b BIGINT NOT NULL, co_view_count INTEGER NOT NULL,
		   refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (product_a, product_b))`,
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

// pvCat is a product_view carrying categoryId (P-033) → feeds the per-category
// popularity pass (P-031).
func pvCat(productID, categoryID int) analytics.Event {
	return analytics.Event{
		Type:     analytics.EventProductView,
		Payload:  map[string]any{"productId": float64(productID), "categoryId": float64(categoryID)},
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

// contains reports whether ids includes target.
func contains(ids []int64, target int64) bool {
	return indexOf(ids, target) >= 0
}

// indexOf returns the position of target in ids, or -1.
func indexOf(ids []int64, target int64) int {
	for i, id := range ids {
		if id == target {
			return i
		}
	}
	return -1
}

func TestIntegration_RefreshRecommendations(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	// Two guest sessions. Session 1: {200,201}. Session 2: {200,202}.
	// Popularity: 200 twice, 201 once, 202 once. Co-views of 200: {201,202}.
	if err := svc.Ingest(ctx, analytics.IngestBatch{
		SessionID: "a1a1a1a1-1111-2222-3333-444444444444",
		Events:    []analytics.Event{pv(200), pv(201)},
	}); err != nil {
		t.Fatal(err)
	}
	if err := svc.Ingest(ctx, analytics.IngestBatch{
		SessionID: "a2a2a2a2-1111-2222-3333-444444444444",
		Events:    []analytics.Event{pv(200), pv(202)},
	}); err != nil {
		t.Fatal(err)
	}
	if err := svc.RefreshRecommendations(ctx); err != nil {
		t.Fatal(err)
	}

	// Shared DB: sibling tests view other products, so assert the relative rank
	// within our own set — 200 (3 views) must out-rank 201/202 (1 view each).
	popular, err := svc.PopularProductIDs(ctx, 1000)
	if err != nil {
		t.Fatal(err)
	}
	if indexOf(popular, 200) < 0 {
		t.Fatalf("product 200 should appear in popularity, got %v", popular)
	}
	if indexOf(popular, 200) > indexOf(popular, 201) || indexOf(popular, 200) > indexOf(popular, 202) {
		t.Fatalf("200 (3 views) must out-rank 201/202 (1 view), got %v", popular)
	}

	similar, err := svc.SimilarProductIDs(ctx, 200, 10)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(similar, 201) || !contains(similar, 202) {
		t.Fatalf("co-views of 200 should include 201 and 202, got %v", similar)
	}
	if contains(similar, 200) {
		t.Fatalf("a product is never its own co-view, got %v", similar)
	}

	// Home personalization: an authed+consented user who viewed 200 gets its
	// co-views (201, 202) back, with the seed (200) excluded.
	const uid = 2001
	if _, err := svc.SetConsent(ctx, uid, true); err != nil {
		t.Fatal(err)
	}
	if err := svc.Ingest(ctx, analytics.IngestBatch{
		SessionID: "a3a3a3a3-1111-2222-3333-444444444444", UserID: u(uid),
		Events: []analytics.Event{pv(200)},
	}); err != nil {
		t.Fatal(err)
	}
	home, err := svc.HomeRecommendationIDs(ctx, uid, 10)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(home, 201) || !contains(home, 202) || contains(home, 200) {
		t.Fatalf("home recs should be {201,202} (seed 200 excluded), got %v", home)
	}
}

func TestIntegration_HomeRecommendations_NoHistoryEmpty(t *testing.T) {
	ctx := context.Background()
	ids, err := newSvc().HomeRecommendationIDs(ctx, 999999, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 0 {
		t.Fatalf("user with no history → empty (popular fallback), got %v", ids)
	}
}

func TestIntegration_PopularPerCategory(t *testing.T) {
	ctx := context.Background()
	svc := newSvc()
	// Unique IDs (shared DB). cat 9001: 8001×3, 8002×1.  cat 9002: 8003×2, 8001×1.
	mustIngest := func(sess string, evs ...analytics.Event) {
		if err := svc.Ingest(ctx, analytics.IngestBatch{SessionID: sess, Events: evs}); err != nil {
			t.Fatal(err)
		}
	}
	mustIngest("b1b1b1b1-1111-2222-3333-444444444444", pvCat(8001, 9001), pvCat(8001, 9001), pvCat(8002, 9001))
	mustIngest("b2b2b2b2-1111-2222-3333-444444444444", pvCat(8001, 9001), pvCat(8003, 9002), pvCat(8003, 9002))
	mustIngest("b3b3b3b3-1111-2222-3333-444444444444", pvCat(8001, 9002))
	if err := svc.RefreshRecommendations(ctx); err != nil {
		t.Fatal(err)
	}

	// cat 9001: 8001 (×3) out-ranks 8002 (×1); 8003 (a 9002 product) is absent.
	c1, err := svc.PopularProductIDsInCategory(ctx, 9001, 100)
	if err != nil {
		t.Fatal(err)
	}
	if indexOf(c1, 8001) < 0 || indexOf(c1, 8002) < 0 {
		t.Fatalf("cat 9001 should contain 8001 + 8002, got %v", c1)
	}
	if indexOf(c1, 8001) > indexOf(c1, 8002) {
		t.Fatalf("8001 (×3) must out-rank 8002 (×1) in cat 9001, got %v", c1)
	}
	if contains(c1, 8003) {
		t.Fatalf("8003 must NOT appear in cat 9001 (cross-category leak), got %v", c1)
	}

	// cat 9002: 8003 (×2) out-ranks 8001 (×1); 8002 absent.
	c2, err := svc.PopularProductIDsInCategory(ctx, 9002, 100)
	if err != nil {
		t.Fatal(err)
	}
	if indexOf(c2, 8003) < 0 || indexOf(c2, 8001) < 0 {
		t.Fatalf("cat 9002 should contain 8003 + 8001, got %v", c2)
	}
	if indexOf(c2, 8003) > indexOf(c2, 8001) {
		t.Fatalf("8003 (×2) must out-rank 8001 (×1) in cat 9002, got %v", c2)
	}
	if contains(c2, 8002) {
		t.Fatalf("8002 must NOT appear in cat 9002 (cross-category leak), got %v", c2)
	}

	// Unknown category → empty (the handler falls back to global).
	empty, err := svc.PopularProductIDsInCategory(ctx, 999999, 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(empty) != 0 {
		t.Fatalf("unknown category should be empty, got %v", empty)
	}

	// Global pass still aggregates 8001 across both categories.
	global, err := svc.PopularProductIDs(ctx, 1000)
	if err != nil {
		t.Fatal(err)
	}
	if !contains(global, 8001) {
		t.Fatalf("global popularity should include 8001, got %v", global)
	}
}
