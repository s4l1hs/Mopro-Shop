//go:build integration

package catalog_test

import (
	"context"
	"sync"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// ensureUGCSchema adds the write-side + Q&A tables/columns onto the catalog
// schema that integration_test.go's TestMain already created.
func ensureUGCSchema(ctx context.Context, t *testing.T) {
	t.Helper()
	// One statement per Exec: the test pool uses the extended protocol, where a
	// multi-statement Exec silently runs only the first statement.
	stmts := []string{
		`ALTER TABLE catalog_schema.product_reviews ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published'`,
		`ALTER TABLE catalog_schema.product_reviews ADD COLUMN IF NOT EXISTS submitted_locale TEXT NOT NULL DEFAULT 'tr'`,
		// DROP+recreate the new tables so the test's schema (incl. FKs) is
		// deterministic regardless of any stale version in the shared test DB.
		`DROP TABLE IF EXISTS catalog_schema.product_answers CASCADE`,
		`DROP TABLE IF EXISTS catalog_schema.product_questions CASCADE`,
		`DROP TABLE IF EXISTS catalog_schema.product_review_revisions CASCADE`,
		`DELETE FROM catalog_schema.product_reviews`,
		`CREATE TABLE IF NOT EXISTS catalog_schema.product_review_revisions (
  id BIGSERIAL PRIMARY KEY, review_id BIGINT NOT NULL REFERENCES catalog_schema.product_reviews(id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL, title TEXT, body TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE IF NOT EXISTS catalog_schema.product_questions (
  id BIGSERIAL PRIMARY KEY, product_id BIGINT NOT NULL, user_id BIGINT NOT NULL, author_name TEXT NOT NULL DEFAULT '',
  body TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'published', submitted_locale TEXT NOT NULL DEFAULT 'tr',
  answer_count INTEGER NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE IF NOT EXISTS catalog_schema.product_answers (
  id BIGSERIAL PRIMARY KEY, question_id BIGINT NOT NULL REFERENCES catalog_schema.product_questions(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL, author_name TEXT NOT NULL DEFAULT '', is_seller BOOLEAN NOT NULL DEFAULT false,
  body TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'published', submitted_locale TEXT NOT NULL DEFAULT 'tr',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
	}
	for _, s := range stmts {
		if _, err := integPool.Exec(ctx, s); err != nil {
			t.Fatalf("ugc schema: %v", err)
		}
	}
}

func TestIntegration_ConcurrentReviewConverges(t *testing.T) {
	ctx := context.Background()
	ensureUGCSchema(ctx, t)
	svc := catalog.NewUGCService(catalog.NewUGCRepository(integPool))
	const productID, userID = 1, 4242

	const n = 8
	var wg sync.WaitGroup
	var mu sync.Mutex
	var okCount, existsCount, other int
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func() {
			defer wg.Done()
			_, err := svc.CreateReview(ctx, catalog.ReviewInput{
				ProductID: productID, UserID: userID, Rating: 5, Body: "great", SubmittedLocale: "tr",
			})
			mu.Lock()
			defer mu.Unlock()
			switch {
			case err == nil:
				okCount++
			case err == catalog.ErrReviewExists:
				existsCount++
			default:
				other++
				t.Errorf("unexpected: %v", err)
			}
		}()
	}
	wg.Wait()
	if okCount != 1 || other != 0 {
		t.Errorf("ok=%d exists=%d other=%d want ok=1 other=0", okCount, existsCount, other)
	}
	var rows int
	if err := integPool.QueryRow(ctx, `SELECT COUNT(*) FROM catalog_schema.product_reviews WHERE product_id=$1 AND user_id=$2`, productID, userID).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Errorf("rows=%d want exactly 1 (converged)", rows)
	}
}

// TestProperty_AnswerCountMatchesRows mirrors PR #18's helpful-count property:
// the denormalized answer_count equals COUNT(*) of published answers after a
// sequence of inserts.
func TestProperty_AnswerCountMatchesRows(t *testing.T) {
	ctx := context.Background()
	ensureUGCSchema(ctx, t)
	repo := catalog.NewUGCRepository(integPool)
	svc := catalog.NewUGCService(repo)

	q, err := svc.CreateQuestion(ctx, catalog.QuestionInput{ProductID: 1, UserID: 1, Body: "q?", AuthorName: "A"})
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 7; i++ {
		if _, err := svc.CreateAnswer(ctx, catalog.AnswerInput{QuestionID: q.ID, UserID: int64(10 + i), Body: "a", AuthorName: "U"}); err != nil {
			t.Fatal(err)
		}
		// Invariant: cache == COUNT(*) after every insert.
		var cache, actual int
		integPool.QueryRow(ctx, `SELECT answer_count FROM catalog_schema.product_questions WHERE id=$1`, q.ID).Scan(&cache)
		integPool.QueryRow(ctx, `SELECT COUNT(*) FROM catalog_schema.product_answers WHERE question_id=$1 AND status='published'`, q.ID).Scan(&actual)
		if cache != actual {
			t.Fatalf("after %d inserts: answer_count=%d COUNT=%d", i+1, cache, actual)
		}
	}
}

func TestIntegration_ReviewCRUD(t *testing.T) {
	ctx := context.Background()
	ensureUGCSchema(ctx, t)
	svc := catalog.NewUGCService(catalog.NewUGCRepository(integPool))

	rec, err := svc.CreateReview(ctx, catalog.ReviewInput{ProductID: 5, UserID: 9, Rating: 4, Title: "ok", Body: "good", SubmittedLocale: "tr"})
	if err != nil {
		t.Fatal(err)
	}
	// Ownership: user 99 can't edit user 9's review.
	if _, err := svc.UpdateReview(ctx, 99, rec.ID, catalog.ReviewInput{ProductID: 5, Rating: 1, Body: "x"}); err != catalog.ErrReviewNotFound {
		t.Errorf("cross-user edit want ErrReviewNotFound, got %v", err)
	}
	// Owner edit creates a revision.
	if _, err := svc.UpdateReview(ctx, 9, rec.ID, catalog.ReviewInput{ProductID: 5, Rating: 3, Body: "edited"}); err != nil {
		t.Fatal(err)
	}
	var revs int
	integPool.QueryRow(ctx, `SELECT COUNT(*) FROM catalog_schema.product_review_revisions WHERE review_id=$1`, rec.ID).Scan(&revs)
	if revs != 2 { // create + edit
		t.Errorf("revisions=%d want 2", revs)
	}
	// Soft delete → excluded from user list + UserReviewID returns 0.
	if err := svc.DeleteReview(ctx, 9, rec.ID); err != nil {
		t.Fatal(err)
	}
	if id, _ := svc.UserReviewID(ctx, 9, 5); id != 0 {
		t.Errorf("deleted review should not count, got id=%d", id)
	}
}
