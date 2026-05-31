// Package help serves public help/FAQ content (categories + articles) from
// help_schema. Read-only, guest-accessible. (Support tickets live in the
// separate internal/support module — Tranche 2b §2.2 decision.)
package help

import "context"

// Category is a help category with a locale-resolved title + article count.
type Category struct {
	Slug         string `json:"slug"`
	Title        string `json:"title"`
	IconName     string `json:"icon_name,omitempty"`
	ArticleCount int    `json:"article_count"`
}

// Article is a help article with locale-resolved title + (markdown) body.
type Article struct {
	Slug     string `json:"slug"`
	Title    string `json:"title"`
	Body     string `json:"body,omitempty"`
	Category string `json:"category_slug,omitempty"`
}

// SearchResult is a search hit: slug + title + a snippet with **matched** terms.
type SearchResult struct {
	Slug         string `json:"slug"`
	Title        string `json:"title"`
	Snippet      string `json:"snippet"`
	CategorySlug string `json:"category_slug"`
}

// Service is the public read surface of the help module.
type Service interface {
	ListCategories(ctx context.Context, locale string) ([]Category, error)
	ListArticles(ctx context.Context, categorySlug, locale string) ([]Article, error)
	GetArticle(ctx context.Context, slug, locale string) (Article, error)
	Search(ctx context.Context, query, locale string) ([]SearchResult, error)
}

// Repository is the storage interface used only by service.go. It returns the
// raw translation maps so the service applies the locale-resolution policy.
type Repository interface {
	ListCategories(ctx context.Context) ([]CategoryRow, error)
	ListArticles(ctx context.Context, categorySlug string) ([]ArticleRow, error)
	GetArticle(ctx context.Context, slug string) (ArticleRow, error)
	SearchArticles(ctx context.Context, query string, limit int) ([]ArticleRow, error)
}

// CategoryRow / ArticleRow carry the raw JSONB translation maps.
type CategoryRow struct {
	Slug         string
	Title        map[string]string
	IconName     string
	ArticleCount int
}

type ArticleRow struct {
	Slug         string
	CategorySlug string
	Title        map[string]string
	Body         map[string]string
}
