package analytics

import (
	"context"
	"time"

	"github.com/google/uuid"
)

// Service is the analytics pipeline's public surface. Ingest + consent + reads
// are wired into core-svc; the retention/rebuild/erasure operations are driven
// by jobs-svc.
type Service interface {
	// Ingest validates a batch, applies the consent gate (authed events dropped
	// unless the user opted in; guest events stored for later merge), appends to
	// the event log, and incrementally upserts the recently-viewed projection.
	// Always succeeds for a well-formed batch — consent denial is silent.
	Ingest(ctx context.Context, batch IngestBatch) error

	// IdentifySession links a guest session to a user (idempotent) and backfills
	// that user's recently-viewed projection from the session's past events
	// (Decision 4 merge-on-auth).
	IdentifySession(ctx context.Context, sessionID string, userID int64) error

	GetConsent(ctx context.Context, userID int64) (Consent, error)
	SetConsent(ctx context.Context, userID int64, enabled bool) (Consent, error)

	// DeleteUserData erases the user's rows across all analytics tables (RTBF,
	// Decision 5). Idempotent. Does not touch consent.
	DeleteUserData(ctx context.Context, userID int64) error

	// RecentlyViewed returns the user's projection rows (product enrichment is
	// the caller's job — no cross-schema JOIN).
	RecentlyViewed(ctx context.Context, userID int64, limit int) ([]RecentlyViewedItem, error)

	// PruneEvents deletes events older than `before`, capping rows per call;
	// returns total deleted. Driven by the jobs-svc retention cron.
	PruneEvents(ctx context.Context, before time.Time, capPerRun int) (int64, error)

	// RebuildRecentlyViewed recomputes the projection from events since `since`
	// (drift backstop). Driven by the jobs-svc rebuild cron.
	RebuildRecentlyViewed(ctx context.Context, since time.Time) error

	// RefreshRecommendations truncate-and-rebuilds the recommendation
	// projections (popular_products + product_co_views) from analytics_events.
	// Driven by the jobs-svc 05:00 cron. Idempotent (full rebuild each run).
	RefreshRecommendations(ctx context.Context) error

	// PopularProductIDs returns the globally most-viewed product IDs (popularity
	// fallback + home rail for non-personalized users). Product enrichment is
	// the caller's job — no cross-schema JOIN.
	PopularProductIDs(ctx context.Context, limit int) ([]int64, error)
	// PopularProductIDsInCategory returns the most-viewed product IDs within one
	// category (P-031, per-category bestseller). Empty until per-category events
	// accrue — callers fall back to PopularProductIDs (the global proxy).
	PopularProductIDsInCategory(ctx context.Context, categoryID int64, limit int) ([]int64, error)

	// HomeRecommendationIDs returns personalized product IDs for an authed,
	// consented user: co-views aggregated over the user's recently-viewed seeds,
	// excluding products the user has already seen. Empty slice when the user has
	// no history or co-view data is too sparse — the caller falls back to
	// PopularProductIDs.
	HomeRecommendationIDs(ctx context.Context, userID int64, limit int) ([]int64, error)

	// SimilarProductIDs returns co-viewed product IDs for a PDP ("Benzer
	// ürünler"). Empty when co-view data is sparse — the caller pads with
	// PopularProductIDs (the §3.3 fallback chain).
	SimilarProductIDs(ctx context.Context, productID int64, limit int) ([]int64, error)
}

// StoredEvent is a row ready for insertion (resolved user_id applied).
type StoredEvent struct {
	SessionID string
	UserID    *int64
	Type      string
	Payload   map[string]any
	ClientTs  time.Time
}

// Repository is the analytics_schema persistence boundary.
type Repository interface {
	InsertEvents(ctx context.Context, batchID uuid.UUID, events []StoredEvent) error
	UpsertRecentlyViewed(ctx context.Context, userID, productID int64, viewedAt time.Time) error

	// ResolveUserID returns the user bound to a session (Decision 4), if any.
	ResolveUserID(ctx context.Context, sessionID string) (int64, bool, error)
	// InsertSessionIdentity binds session→user; ON CONFLICT (session_id) DO NOTHING.
	InsertSessionIdentity(ctx context.Context, sessionID string, userID int64) error
	// BackfillRecentlyViewed replays a session's product_view events into the
	// user's projection (used right after identify).
	BackfillRecentlyViewed(ctx context.Context, sessionID string, userID int64) error

	GetConsent(ctx context.Context, userID int64) (Consent, bool, error)
	UpsertConsent(ctx context.Context, userID int64, enabled bool) (Consent, error)

	DeleteUserData(ctx context.Context, userID int64) error
	ListRecentlyViewed(ctx context.Context, userID int64, limit int) ([]RecentlyViewedItem, error)

	PruneEvents(ctx context.Context, before time.Time, capPerRun int) (int64, error)
	RebuildRecentlyViewed(ctx context.Context, since time.Time) error

	// RebuildPopular truncates popular_products and recomputes 'global' scope
	// from product_view events on/after `since`, keeping the top `limit`.
	RebuildPopular(ctx context.Context, since time.Time, limit int) error
	// RebuildCoViews truncates product_co_views and recomputes co-occurrence
	// from product_view pairs sharing a session within `windowSeconds`, keeping
	// the top `capPerProduct` partners per product.
	RebuildCoViews(ctx context.Context, windowSeconds, capPerProduct int) error

	// PopularGlobalIDs returns the top global product IDs by view_count.
	PopularGlobalIDs(ctx context.Context, limit int) ([]int64, error)
	// PopularCategoryIDs returns the top product IDs by view_count within one
	// category (scope 'category:<id>', P-031).
	PopularCategoryIDs(ctx context.Context, categoryID int64, limit int) ([]int64, error)
	// CoViewIDs returns the top co-viewed partners of a single product.
	CoViewIDs(ctx context.Context, productID int64, limit int) ([]int64, error)
	// CoViewIDsForSeeds aggregates co-views across multiple seed products
	// (home personalization), excluding the seeds themselves, ranked by summed
	// co-view count.
	CoViewIDsForSeeds(ctx context.Context, seedIDs []int64, limit int) ([]int64, error)
}
