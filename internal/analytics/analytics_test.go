package analytics

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
)

const validSession = "11111111-2222-3333-4444-555555555555"

// fakeRepo is an in-memory Repository for service-logic tests.
type fakeRepo struct {
	consent    map[int64]Consent
	identities map[string]int64
	events     []StoredEvent
	recently   map[[2]int64]*RecentlyViewedItem
	popular    []int64           // ordered global-popular product IDs
	coViews    map[int64][]int64 // product_a → ordered partners
	refreshed  bool              // RefreshRecommendations was invoked
}

func newFakeRepo() *fakeRepo {
	return &fakeRepo{
		consent:    map[int64]Consent{},
		identities: map[string]int64{},
		recently:   map[[2]int64]*RecentlyViewedItem{},
		coViews:    map[int64][]int64{},
	}
}

func (f *fakeRepo) InsertEvents(_ context.Context, _ uuid.UUID, events []StoredEvent) error {
	f.events = append(f.events, events...)
	return nil
}
func (f *fakeRepo) UpsertRecentlyViewed(_ context.Context, userID, productID int64, ts time.Time) error {
	k := [2]int64{userID, productID}
	if it, ok := f.recently[k]; ok {
		it.ViewCount++
		if ts.After(it.LastViewedAt) {
			it.LastViewedAt = ts
		}
		return nil
	}
	f.recently[k] = &RecentlyViewedItem{ProductID: productID, LastViewedAt: ts, ViewCount: 1}
	return nil
}
func (f *fakeRepo) ResolveUserID(_ context.Context, sessionID string) (int64, bool, error) {
	uid, ok := f.identities[sessionID]
	return uid, ok, nil
}
func (f *fakeRepo) InsertSessionIdentity(_ context.Context, sessionID string, userID int64) error {
	if _, ok := f.identities[sessionID]; !ok {
		f.identities[sessionID] = userID
	}
	return nil
}
func (f *fakeRepo) BackfillRecentlyViewed(_ context.Context, sessionID string, userID int64) error {
	for _, e := range f.events {
		if e.SessionID == sessionID && e.Type == EventProductView {
			if pid, ok := payloadInt64(e.Payload, "productId"); ok {
				_ = f.UpsertRecentlyViewed(context.Background(), userID, pid, e.ClientTs)
			}
		}
	}
	return nil
}
func (f *fakeRepo) GetConsent(_ context.Context, userID int64) (Consent, bool, error) {
	c, ok := f.consent[userID]
	return c, ok, nil
}
func (f *fakeRepo) UpsertConsent(_ context.Context, userID int64, enabled bool) (Consent, error) {
	now := time.Now()
	c := Consent{UserID: userID, AnalyticsEnabled: enabled}
	if enabled {
		c.ConsentedAt = &now
	} else {
		c.RevokedAt = &now
	}
	f.consent[userID] = c
	return c, nil
}
func (f *fakeRepo) DeleteUserData(_ context.Context, userID int64) error {
	kept := f.events[:0]
	for _, e := range f.events {
		if e.UserID == nil || *e.UserID != userID {
			kept = append(kept, e)
		}
	}
	f.events = kept
	for k := range f.recently {
		if k[0] == userID {
			delete(f.recently, k)
		}
	}
	for s, uid := range f.identities {
		if uid == userID {
			delete(f.identities, s)
		}
	}
	return nil
}
func (f *fakeRepo) ListRecentlyViewed(_ context.Context, userID int64, limit int) ([]RecentlyViewedItem, error) {
	var out []RecentlyViewedItem
	for k, it := range f.recently {
		if k[0] == userID {
			out = append(out, *it)
		}
	}
	if len(out) > limit {
		out = out[:limit]
	}
	return out, nil
}
func (f *fakeRepo) PruneEvents(_ context.Context, _ time.Time, _ int) (int64, error) { return 0, nil }
func (f *fakeRepo) RebuildRecentlyViewed(_ context.Context, _ time.Time) error       { return nil }

func (f *fakeRepo) RebuildPopular(_ context.Context, _ time.Time, _ int) error {
	f.refreshed = true
	return nil
}
func (f *fakeRepo) RebuildCoViews(_ context.Context, _, _ int) error { return nil }

func (f *fakeRepo) PopularGlobalIDs(_ context.Context, limit int) ([]int64, error) {
	return clampSlice(f.popular, limit), nil
}

func (f *fakeRepo) CoViewIDs(_ context.Context, productID int64, limit int) ([]int64, error) {
	return clampSlice(f.coViews[productID], limit), nil
}

func (f *fakeRepo) CoViewIDsForSeeds(_ context.Context, seedIDs []int64, limit int) ([]int64, error) {
	seen := map[int64]bool{}
	for _, s := range seedIDs {
		seen[s] = true
	}
	var out []int64
	for _, s := range seedIDs {
		for _, p := range f.coViews[s] {
			if !seen[p] {
				seen[p] = true
				out = append(out, p)
			}
		}
	}
	return clampSlice(out, limit), nil
}

func clampSlice(s []int64, limit int) []int64 {
	if limit > 0 && len(s) > limit {
		return s[:limit]
	}
	return s
}

func ptr(i int64) *int64 { return &i }

func TestValidateBatch(t *testing.T) {
	pv := Event{Type: EventProductView, Payload: map[string]any{"productId": float64(42)}}
	cases := []struct {
		name    string
		batch   IngestBatch
		wantErr error
	}{
		{"valid", IngestBatch{SessionID: validSession, Events: []Event{pv}}, nil},
		// P-033: product_view accepts an OPTIONAL categoryId additively — the "valid"
		// case above (productId only) is the backward-compat path; this is the new path.
		{"product_view with categoryId (additive, P-033)", IngestBatch{SessionID: validSession, Events: []Event{{Type: EventProductView, Payload: map[string]any{"productId": float64(42), "categoryId": float64(5)}}}}, nil},
		{"bad session", IngestBatch{SessionID: "nope", Events: []Event{pv}}, ErrInvalidSession},
		{"empty", IngestBatch{SessionID: validSession}, ErrEmptyBatch},
		{"unknown type", IngestBatch{SessionID: validSession, Events: []Event{{Type: "frobnicate", Payload: map[string]any{}}}}, ErrUnknownEventType},
		{"missing field", IngestBatch{SessionID: validSession, Events: []Event{{Type: EventProductView, Payload: map[string]any{}}}}, ErrMissingPayloadField},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := ValidateBatch(tc.batch); got != tc.wantErr {
				t.Fatalf("ValidateBatch = %v, want %v", got, tc.wantErr)
			}
		})
	}
}

// TestValidateBatch_ProductViewCategoryIdPreserved pins the additive contract
// (P-033): validation does not strip categoryId, so it survives into the JSONB
// payload that P-031's RebuildPopular will GROUP BY.
func TestValidateBatch_ProductViewCategoryIdPreserved(t *testing.T) {
	ev := Event{Type: EventProductView, Payload: map[string]any{"productId": float64(42), "categoryId": float64(5)}}
	if err := ValidateBatch(IngestBatch{SessionID: validSession, Events: []Event{ev}}); err != nil {
		t.Fatalf("ValidateBatch = %v, want nil", err)
	}
	if ev.Payload["categoryId"] != float64(5) {
		t.Fatalf("categoryId not preserved on the payload: got %v", ev.Payload["categoryId"])
	}
}

func TestValidateBatch_TooLarge(t *testing.T) {
	evs := make([]Event, MaxBatchSize+1)
	for i := range evs {
		evs[i] = Event{Type: EventPageView, Payload: map[string]any{"path": "/"}}
	}
	if err := ValidateBatch(IngestBatch{SessionID: validSession, Events: evs}); err != ErrBatchTooLarge {
		t.Fatalf("want ErrBatchTooLarge, got %v", err)
	}
}

func TestNormalizeSearchQuery(t *testing.T) {
	cases := map[string]string{
		"  Ayakkabı!! ":        "ayakkabı",
		"NIKE   air   max":     "nike air max",
		"<script>alert(1)</s>": "scriptalert1s",
	}
	for in, want := range cases {
		if got := NormalizeSearchQuery(in); got != want {
			t.Errorf("NormalizeSearchQuery(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestIngest_GuestStored_NoProjection(t *testing.T) {
	repo := newFakeRepo()
	svc := NewService(repo)
	err := svc.Ingest(context.Background(), IngestBatch{
		SessionID: validSession,
		Events:    []Event{{Type: EventProductView, Payload: map[string]any{"productId": float64(7)}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(repo.events) != 1 {
		t.Fatalf("guest event should be stored, got %d", len(repo.events))
	}
	if len(repo.recently) != 0 {
		t.Fatalf("guest should not project recently-viewed, got %d", len(repo.recently))
	}
}

func TestIngest_AuthedConsentOff_Dropped(t *testing.T) {
	repo := newFakeRepo()
	repo.consent[5] = Consent{UserID: 5, AnalyticsEnabled: false}
	svc := NewService(repo)
	err := svc.Ingest(context.Background(), IngestBatch{
		SessionID: validSession,
		UserID:    ptr(5),
		Events:    []Event{{Type: EventProductView, Payload: map[string]any{"productId": float64(7)}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(repo.events) != 0 {
		t.Fatalf("consent-off events must be dropped, got %d", len(repo.events))
	}
}

func TestIngest_AuthedConsentOn_StoredAndProjected(t *testing.T) {
	repo := newFakeRepo()
	repo.consent[5] = Consent{UserID: 5, AnalyticsEnabled: true}
	svc := NewService(repo)
	err := svc.Ingest(context.Background(), IngestBatch{
		SessionID: validSession,
		UserID:    ptr(5),
		Events: []Event{
			{Type: EventProductView, Payload: map[string]any{"productId": float64(7)}, ClientTs: time.Now()},
			{Type: EventPageView, Payload: map[string]any{"path": "/"}},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(repo.events) != 2 {
		t.Fatalf("want 2 events, got %d", len(repo.events))
	}
	if repo.recently[[2]int64{5, 7}] == nil {
		t.Fatal("product_view should upsert recently-viewed for authed user")
	}
}

func TestIngest_SearchRawTextStripped(t *testing.T) {
	repo := newFakeRepo()
	repo.consent[5] = Consent{UserID: 5, AnalyticsEnabled: true}
	svc := NewService(repo)
	err := svc.Ingest(context.Background(), IngestBatch{
		SessionID: validSession,
		UserID:    ptr(5),
		Events: []Event{{Type: EventSearch, Payload: map[string]any{
			"normalizedQuery": "ayakkabı", "resultCount": float64(3), "query": "Ayakkabı NEREDE",
		}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := repo.events[0].Payload["query"]; ok {
		t.Fatal("raw search text 'query' must be stripped (Option A)")
	}
	if repo.events[0].Payload["normalizedQuery"] != "ayakkabı" {
		t.Fatal("normalized intent must be preserved")
	}
}

func TestIngest_ResolvesViaSessionIdentity(t *testing.T) {
	repo := newFakeRepo()
	repo.identities[validSession] = 9
	repo.consent[9] = Consent{UserID: 9, AnalyticsEnabled: false}
	svc := NewService(repo)
	// No explicit UserID, but the session is identified → consent gate applies.
	err := svc.Ingest(context.Background(), IngestBatch{
		SessionID: validSession,
		Events:    []Event{{Type: EventPageView, Payload: map[string]any{"path": "/"}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(repo.events) != 0 {
		t.Fatal("identified session with consent off must drop events")
	}
}

func TestIdentifySession_InvalidSession(t *testing.T) {
	svc := NewService(newFakeRepo())
	if err := svc.IdentifySession(context.Background(), "bad", 1); err != ErrInvalidSession {
		t.Fatalf("want ErrInvalidSession, got %v", err)
	}
}

func TestSetConsent_Toggle(t *testing.T) {
	svc := NewService(newFakeRepo())
	on, _ := svc.SetConsent(context.Background(), 1, true)
	if !on.AnalyticsEnabled || on.ConsentedAt == nil {
		t.Fatal("enable should set consentedAt")
	}
	off, _ := svc.SetConsent(context.Background(), 1, false)
	if off.AnalyticsEnabled || off.RevokedAt == nil {
		t.Fatal("disable should set revokedAt")
	}
}

func TestHomeRecommendationIDs_NoHistory_Empty(t *testing.T) {
	repo := newFakeRepo()
	ids, err := NewService(repo).HomeRecommendationIDs(context.Background(), 9, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 0 {
		t.Fatalf("no history → empty (caller falls back to popular), got %v", ids)
	}
}

func TestHomeRecommendationIDs_AggregatesCoViewsExcludingSeeds(t *testing.T) {
	repo := newFakeRepo()
	// User viewed product 1 and 2.
	repo.recently[[2]int64{9, 1}] = &RecentlyViewedItem{ProductID: 1}
	repo.recently[[2]int64{9, 2}] = &RecentlyViewedItem{ProductID: 2}
	// Co-views: 1→{2,3}, 2→{3,4}. Seeds (1,2) must be excluded; 3 appears via both.
	repo.coViews[1] = []int64{2, 3}
	repo.coViews[2] = []int64{3, 4}
	ids, err := NewService(repo).HomeRecommendationIDs(context.Background(), 9, 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, id := range ids {
		if id == 1 || id == 2 {
			t.Fatalf("seed products must be excluded, got %v", ids)
		}
	}
	if len(ids) != 2 || ids[0] != 3 || ids[1] != 4 {
		t.Fatalf("want [3 4] (deduped, seeds excluded), got %v", ids)
	}
}

func TestSimilarProductIDs_ReturnsCoViews(t *testing.T) {
	repo := newFakeRepo()
	repo.coViews[42] = []int64{7, 8, 9}
	ids, err := NewService(repo).SimilarProductIDs(context.Background(), 42, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 2 || ids[0] != 7 || ids[1] != 8 {
		t.Fatalf("want top-2 co-views [7 8], got %v", ids)
	}
}

func TestPopularProductIDs_ClampsLimit(t *testing.T) {
	repo := newFakeRepo()
	repo.popular = []int64{1, 2, 3, 4, 5}
	ids, err := NewService(repo).PopularProductIDs(context.Background(), 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 3 {
		t.Fatalf("want 3 popular IDs, got %v", ids)
	}
}

func TestRefreshRecommendations_RebuildsBothTables(t *testing.T) {
	repo := newFakeRepo()
	if err := NewService(repo).RefreshRecommendations(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !repo.refreshed {
		t.Fatal("RefreshRecommendations must rebuild popular_products")
	}
}
