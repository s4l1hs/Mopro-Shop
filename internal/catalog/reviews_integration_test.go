//go:build integration

package catalog_test

// Integration tests for the reviews helpful-vote + sort + pagination + summary
// surface. Run against the same ephemeral PG16 as integration_test.go:
//
//	go test -tags=integration -v ./internal/catalog/...
//
// Each test uses a distinct product_id so they do not interfere (the tables are
// created once in TestMain's setupSchema and shared across tests).

import (
	"context"
	"math/rand"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/mopro/platform/internal/catalog"
)

var baseTime = time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)

func newReviewsSvc() catalog.Service {
	return catalog.NewService(catalog.NewRepository(integPool), "TRY", "tr-TR")
}

type seedSpec struct {
	userID    int64
	rating    int
	helpful   int
	createdAt time.Time
}

func seedReview(t *testing.T, productID int64, s seedSpec) int64 {
	t.Helper()
	var id int64
	err := integPool.QueryRow(context.Background(),
		`INSERT INTO catalog_schema.product_reviews
		   (product_id, user_id, rating, title, body, helpful_count, created_at)
		 VALUES ($1,$2,$3,'t','b',$4,$5) RETURNING id`,
		productID, s.userID, s.rating, s.helpful, s.createdAt).Scan(&id)
	if err != nil {
		t.Fatalf("seedReview: %v", err)
	}
	return id
}

func voteRowCount(t *testing.T, reviewID int64) int {
	t.Helper()
	var n int
	if err := integPool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM catalog_schema.review_helpful_votes WHERE review_id=$1`, reviewID).Scan(&n); err != nil {
		t.Fatalf("voteRowCount: %v", err)
	}
	return n
}

func cachedHelpfulCount(t *testing.T, reviewID int64) int {
	t.Helper()
	var n int
	if err := integPool.QueryRow(context.Background(),
		`SELECT helpful_count FROM catalog_schema.product_reviews WHERE id=$1`, reviewID).Scan(&n); err != nil {
		t.Fatalf("cachedHelpfulCount: %v", err)
	}
	return n
}

// TestIntegration_ToggleHelpfulVote_HappyPath exercises vote → unvote → vote and
// asserts the cache + authoritative rows track each transition.
func TestIntegration_ToggleHelpfulVote_HappyPath(t *testing.T) {
	ctx := context.Background()
	svc := newReviewsSvc()
	const productID = 9001
	rid := seedReview(t, productID, seedSpec{userID: 1, rating: 5, helpful: 0, createdAt: baseTime})

	// 1) vote on
	res, err := svc.ToggleHelpfulVote(ctx, rid, 100)
	if err != nil {
		t.Fatalf("toggle on: %v", err)
	}
	if !res.Voted || res.HelpfulCount != 1 {
		t.Fatalf("toggle on: want voted=true count=1 got %+v", res)
	}
	if voteRowCount(t, rid) != 1 || cachedHelpfulCount(t, rid) != 1 {
		t.Fatalf("after on: rows=%d cache=%d", voteRowCount(t, rid), cachedHelpfulCount(t, rid))
	}

	// 2) vote off (toggle)
	res, err = svc.ToggleHelpfulVote(ctx, rid, 100)
	if err != nil {
		t.Fatalf("toggle off: %v", err)
	}
	if res.Voted || res.HelpfulCount != 0 {
		t.Fatalf("toggle off: want voted=false count=0 got %+v", res)
	}
	if voteRowCount(t, rid) != 0 || cachedHelpfulCount(t, rid) != 0 {
		t.Fatalf("after off: rows=%d cache=%d", voteRowCount(t, rid), cachedHelpfulCount(t, rid))
	}

	// 3) vote on again
	res, err = svc.ToggleHelpfulVote(ctx, rid, 100)
	if err != nil {
		t.Fatalf("toggle on2: %v", err)
	}
	if !res.Voted || res.HelpfulCount != 1 {
		t.Fatalf("toggle on2: want voted=true count=1 got %+v", res)
	}
}

// TestIntegration_ConcurrentToggle spawns N goroutines that toggle the SAME
// (review, user) pair simultaneously. The PRIMARY KEY plus SERIALIZABLE + retry
// must converge to a single consistent state: exactly N%2 vote rows, and the
// helpful_count cache must match. Same shape as PR #10's
// TestCronProperty_ConcurrentIdempotency.
func TestIntegration_ConcurrentToggle(t *testing.T) {
	ctx := context.Background()
	svc := newReviewsSvc()
	const productID = 9002
	const userID = 555
	const N = 7 // odd → net 1 row
	rid := seedReview(t, productID, seedSpec{userID: 1, rating: 4, helpful: 0, createdAt: baseTime})

	var wg sync.WaitGroup
	errs := make([]error, N)
	wg.Add(N)
	for i := 0; i < N; i++ {
		go func(idx int) {
			defer wg.Done()
			_, errs[idx] = svc.ToggleHelpfulVote(ctx, rid, userID)
		}(i)
	}
	wg.Wait()

	for i, e := range errs {
		if e != nil {
			t.Fatalf("goroutine %d errored: %v", i, e)
		}
	}
	wantRows := N % 2
	if got := voteRowCount(t, rid); got != wantRows {
		t.Fatalf("vote rows: want %d got %d", wantRows, got)
	}
	if got := cachedHelpfulCount(t, rid); got != wantRows {
		t.Fatalf("cached helpful_count: want %d got %d", wantRows, got)
	}
	t.Logf("concurrent toggle: N=%d goroutines converged to %d vote row(s); helpful_count=%d (no errors)",
		N, voteRowCount(t, rid), cachedHelpfulCount(t, rid))
}

// TestProperty_HelpfulCountMatchesVoteRows asserts the cache invariant holds after
// every toggle across a random sequence of users. Mirrors PR #10's
// TestCronProperty_PaymentsMadeMatchesCount.
func TestProperty_HelpfulCountMatchesVoteRows(t *testing.T) {
	ctx := context.Background()
	svc := newReviewsSvc()
	const productID = 9003
	rid := seedReview(t, productID, seedSpec{userID: 1, rating: 3, helpful: 0, createdAt: baseTime})

	users := []int64{100, 101, 102, 103, 104}
	rng := rand.New(rand.NewSource(42))
	const steps = 200
	for i := 0; i < steps; i++ {
		u := users[rng.Intn(len(users))]
		if _, err := svc.ToggleHelpfulVote(ctx, rid, u); err != nil {
			t.Fatalf("step %d toggle(user=%d): %v", i, u, err)
		}
		cache := cachedHelpfulCount(t, rid)
		rows := voteRowCount(t, rid)
		if cache != rows {
			t.Fatalf("step %d: helpful_count cache=%d != vote rows=%d", i, cache, rows)
		}
	}
	t.Logf("property: helpful_count == COUNT(*) vote rows held across %d random toggles", steps)
}

// reviewsFixture seeds a deterministic 10-review fixture and returns the specs by
// review id so expected orderings can be computed in Go.
func reviewsFixture(t *testing.T, productID int64) map[int64]seedSpec {
	t.Helper()
	specs := []seedSpec{
		{userID: 1, rating: 5, helpful: 2, createdAt: baseTime.Add(1 * time.Hour)},
		{userID: 2, rating: 1, helpful: 9, createdAt: baseTime.Add(2 * time.Hour)},
		{userID: 3, rating: 3, helpful: 0, createdAt: baseTime.Add(3 * time.Hour)},
		{userID: 4, rating: 5, helpful: 5, createdAt: baseTime.Add(4 * time.Hour)},
		{userID: 5, rating: 2, helpful: 1, createdAt: baseTime.Add(5 * time.Hour)},
		{userID: 6, rating: 4, helpful: 7, createdAt: baseTime.Add(6 * time.Hour)},
		{userID: 7, rating: 4, helpful: 3, createdAt: baseTime.Add(7 * time.Hour)},
		{userID: 8, rating: 1, helpful: 0, createdAt: baseTime.Add(8 * time.Hour)},
		{userID: 9, rating: 3, helpful: 4, createdAt: baseTime.Add(9 * time.Hour)},
		{userID: 10, rating: 5, helpful: 6, createdAt: baseTime.Add(10 * time.Hour)},
	}
	out := make(map[int64]seedSpec, len(specs))
	for _, s := range specs {
		id := seedReview(t, productID, s)
		out[id] = s
	}
	return out
}

// expectedOrder returns review ids sorted by the given comparator, applying the
// same id-DESC tiebreaker the SQL uses.
func expectedOrder(specs map[int64]seedSpec, less func(a, b int64) bool) []int64 {
	ids := make([]int64, 0, len(specs))
	for id := range specs {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return less(ids[i], ids[j]) })
	return ids
}

func idsOf(rows []catalog.ProductReviewRow) []int64 {
	out := make([]int64, len(rows))
	for i, r := range rows {
		out[i] = r.ID
	}
	return out
}

func eqIDs(a, b []int64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestIntegration_ListReviews_Sorting(t *testing.T) {
	ctx := context.Background()
	svc := newReviewsSvc()
	const productID = 9004
	specs := reviewsFixture(t, productID)

	cases := []struct {
		name string
		sort catalog.ReviewSort
		less func(a, b int64) bool
	}{
		{"newest", catalog.ReviewSortNewest, func(a, b int64) bool {
			if !specs[a].createdAt.Equal(specs[b].createdAt) {
				return specs[a].createdAt.After(specs[b].createdAt)
			}
			return a > b
		}},
		{"highest", catalog.ReviewSortHighest, func(a, b int64) bool {
			if specs[a].rating != specs[b].rating {
				return specs[a].rating > specs[b].rating
			}
			if !specs[a].createdAt.Equal(specs[b].createdAt) {
				return specs[a].createdAt.After(specs[b].createdAt)
			}
			return a > b
		}},
		{"lowest", catalog.ReviewSortLowest, func(a, b int64) bool {
			if specs[a].rating != specs[b].rating {
				return specs[a].rating < specs[b].rating
			}
			if !specs[a].createdAt.Equal(specs[b].createdAt) {
				return specs[a].createdAt.After(specs[b].createdAt)
			}
			return a > b
		}},
		{"helpful", catalog.ReviewSortHelpful, func(a, b int64) bool {
			if specs[a].helpful != specs[b].helpful {
				return specs[a].helpful > specs[b].helpful
			}
			if !specs[a].createdAt.Equal(specs[b].createdAt) {
				return specs[a].createdAt.After(specs[b].createdAt)
			}
			return a > b
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rows, total, err := svc.ListReviews(ctx, productID, tc.sort, 1, 10, 0)
			if err != nil {
				t.Fatalf("ListReviews: %v", err)
			}
			if total != 10 {
				t.Fatalf("total: want 10 got %d", total)
			}
			want := expectedOrder(specs, tc.less)
			if got := idsOf(rows); !eqIDs(got, want) {
				t.Errorf("%s order mismatch:\n got=%v\nwant=%v", tc.name, got, want)
			}
		})
	}
}

func TestIntegration_ListReviews_Pagination(t *testing.T) {
	ctx := context.Background()
	svc := newReviewsSvc()
	const productID = 9005
	reviewsFixture(t, productID)

	seen := map[int64]int{}
	var totalSeen int
	wantPageLens := []int{4, 4, 2}
	for page := 1; page <= 3; page++ {
		rows, total, err := svc.ListReviews(ctx, productID, catalog.ReviewSortNewest, page, 4, 0)
		if err != nil {
			t.Fatalf("page %d: %v", page, err)
		}
		if total != 10 {
			t.Fatalf("page %d total: want 10 got %d", page, total)
		}
		if len(rows) != wantPageLens[page-1] {
			t.Fatalf("page %d len: want %d got %d", page, wantPageLens[page-1], len(rows))
		}
		for _, r := range rows {
			seen[r.ID]++
			totalSeen++
		}
	}
	if totalSeen != 10 {
		t.Fatalf("total rows across pages: want 10 got %d", totalSeen)
	}
	for id, c := range seen {
		if c != 1 {
			t.Errorf("review %d appeared %d times (overlap/dup)", id, c)
		}
	}
	if len(seen) != 10 {
		t.Errorf("distinct reviews seen: want 10 got %d", len(seen))
	}
}

func TestIntegration_ReviewsSummary(t *testing.T) {
	ctx := context.Background()
	svc := newReviewsSvc()
	const productID = 9006
	// ratings: 5,5,4,3,1 → avg 3.6, dist{5:2,4:1,3:1,2:0,1:1}, total 5
	for i, r := range []int{5, 5, 4, 3, 1} {
		seedReview(t, productID, seedSpec{userID: int64(i + 1), rating: r, helpful: 0, createdAt: baseTime.Add(time.Duration(i) * time.Hour)})
	}
	s, err := svc.ReviewsSummary(ctx, productID)
	if err != nil {
		t.Fatalf("ReviewsSummary: %v", err)
	}
	if s.TotalCount != 5 {
		t.Errorf("total: want 5 got %d", s.TotalCount)
	}
	if s.Average < 3.59 || s.Average > 3.61 {
		t.Errorf("average: want ~3.6 got %v", s.Average)
	}
	want := map[int]int{1: 1, 2: 0, 3: 1, 4: 1, 5: 2}
	for k, v := range want {
		if s.Distribution[k] != v {
			t.Errorf("distribution[%d]: want %d got %d", k, v, s.Distribution[k])
		}
	}

	// Summary must be identical no matter which page is requested (it is computed
	// independently of page) — assert two calls are equal.
	s2, _ := svc.ReviewsSummary(ctx, productID)
	if s2.TotalCount != s.TotalCount || s2.Average != s.Average {
		t.Errorf("summary not stable across calls: %+v vs %+v", s, s2)
	}
}

func TestIntegration_VotedByCurrentUser(t *testing.T) {
	ctx := context.Background()
	svc := newReviewsSvc()
	const productID = 9007
	rid := seedReview(t, productID, seedSpec{userID: 1, rating: 5, helpful: 0, createdAt: baseTime})

	// User 100 votes.
	if _, err := svc.ToggleHelpfulVote(ctx, rid, 100); err != nil {
		t.Fatalf("toggle: %v", err)
	}

	check := func(viewer int64, want bool) {
		rows, _, err := svc.ListReviews(ctx, productID, catalog.ReviewSortNewest, 1, 10, viewer)
		if err != nil {
			t.Fatalf("ListReviews(viewer=%d): %v", viewer, err)
		}
		if len(rows) != 1 {
			t.Fatalf("viewer=%d: want 1 row got %d", viewer, len(rows))
		}
		if rows[0].VotedByCurrentUser != want {
			t.Errorf("viewer=%d: VotedByCurrentUser want %v got %v", viewer, want, rows[0].VotedByCurrentUser)
		}
	}
	check(100, true) // the voter
	check(200, false)
	check(0, false) // guest
}
