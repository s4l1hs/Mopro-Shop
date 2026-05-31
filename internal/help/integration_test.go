//go:build integration

package help_test

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/help"
)

const defaultDSN = "postgres://ecom_admin:test123@localhost:6433/mopro_ecom"

var pool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("HELP_TEST_DSN")
	if dsn == "" {
		dsn = defaultDSN
	}
	ctx := context.Background()
	var err error
	pool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "help integration: pool: %v\n", err)
		os.Exit(1)
	}
	ddl := `
CREATE SCHEMA IF NOT EXISTS help_schema;
DROP TABLE IF EXISTS help_schema.help_articles CASCADE;
DROP TABLE IF EXISTS help_schema.help_categories CASCADE;
CREATE TABLE help_schema.help_categories (id BIGSERIAL PRIMARY KEY, slug TEXT UNIQUE,
  title_translations JSONB NOT NULL, icon_name TEXT, sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE help_schema.help_articles (id BIGSERIAL PRIMARY KEY,
  category_id BIGINT NOT NULL REFERENCES help_schema.help_categories(id) ON DELETE CASCADE,
  slug TEXT UNIQUE, title_translations JSONB NOT NULL, body_translations JSONB NOT NULL,
  sort_order INT NOT NULL DEFAULT 0, is_published BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
INSERT INTO help_schema.help_categories (slug, title_translations, sort_order)
  VALUES ('returns', '{"tr":"İadeler","en":"Returns"}', 1);
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order, is_published)
  SELECT id, 'start-return', '{"tr":"İade başlat","en":"Start a return"}',
         '{"tr":"İade talebini sipariş detayından başlat.","en":"Start from the order detail."}', 1, true
  FROM help_schema.help_categories WHERE slug='returns';
INSERT INTO help_schema.help_articles (category_id, slug, title_translations, body_translations, sort_order, is_published)
  SELECT id, 'draft', '{"tr":"Taslak","en":"Draft"}', '{"tr":"gizli iade","en":"hidden"}', 2, false
  FROM help_schema.help_categories WHERE slug='returns';`
	if _, err := pool.Exec(ctx, ddl); err != nil {
		fmt.Fprintf(os.Stderr, "help integration: ddl: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	pool.Close()
	os.Exit(code)
}

func TestIntegration_HelpRepo(t *testing.T) {
	ctx := context.Background()
	svc := help.NewService(help.NewRepository(pool), nil)

	cats, err := svc.ListCategories(ctx, "tr")
	if err != nil || len(cats) != 1 {
		t.Fatalf("categories: %v len=%d", err, len(cats))
	}
	if cats[0].Title != "İadeler" || cats[0].ArticleCount != 1 { // only published counted
		t.Errorf("category resolve/count: %+v", cats[0])
	}

	// is_published=false article excluded from listing.
	arts, err := svc.ListArticles(ctx, "returns", "en")
	if err != nil || len(arts) != 1 || arts[0].Slug != "start-return" {
		t.Fatalf("articles: %v %+v", err, arts)
	}

	// Search hits the published article; snippet bolds the term.
	res, err := svc.Search(ctx, "iade", "tr")
	if err != nil {
		t.Fatal(err)
	}
	if len(res) != 1 {
		t.Fatalf("search expected 1 published hit, got %d", len(res))
	}
	if res[0].Slug != "start-return" {
		t.Errorf("search slug: %s", res[0].Slug)
	}
}
