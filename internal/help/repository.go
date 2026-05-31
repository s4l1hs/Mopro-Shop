package help

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a help Repository backed by a pgx pool.
func NewRepository(pool *pgxpool.Pool) Repository { return &pgxRepository{pool: pool} }

func (r *pgxRepository) ListCategories(ctx context.Context) ([]CategoryRow, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT c.slug, c.title_translations, COALESCE(c.icon_name,''),
		        (SELECT COUNT(*) FROM help_schema.help_articles a
		           WHERE a.category_id = c.id AND a.is_published) AS n
		   FROM help_schema.help_categories c
		  ORDER BY c.sort_order, c.id`)
	if err != nil {
		return nil, fmt.Errorf("help.repo: list categories: %w", err)
	}
	defer rows.Close()
	var out []CategoryRow
	for rows.Next() {
		var c CategoryRow
		var title []byte
		if err := rows.Scan(&c.Slug, &title, &c.IconName, &c.ArticleCount); err != nil {
			return nil, fmt.Errorf("help.repo: scan category: %w", err)
		}
		c.Title = decode(title)
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *pgxRepository) ListArticles(ctx context.Context, categorySlug string) ([]ArticleRow, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT a.slug, $1, a.title_translations
		   FROM help_schema.help_articles a
		   JOIN help_schema.help_categories c ON c.id = a.category_id
		  WHERE c.slug = $1 AND a.is_published
		  ORDER BY a.sort_order, a.id`, categorySlug)
	if err != nil {
		return nil, fmt.Errorf("help.repo: list articles: %w", err)
	}
	defer rows.Close()
	var out []ArticleRow
	for rows.Next() {
		var a ArticleRow
		var title []byte
		if err := rows.Scan(&a.Slug, &a.CategorySlug, &title); err != nil {
			return nil, fmt.Errorf("help.repo: scan article: %w", err)
		}
		a.Title = decode(title)
		out = append(out, a)
	}
	return out, rows.Err()
}

func (r *pgxRepository) GetArticle(ctx context.Context, slug string) (ArticleRow, error) {
	var a ArticleRow
	var title, body []byte
	err := r.pool.QueryRow(ctx,
		`SELECT a.slug, c.slug, a.title_translations, a.body_translations
		   FROM help_schema.help_articles a
		   JOIN help_schema.help_categories c ON c.id = a.category_id
		  WHERE a.slug = $1 AND a.is_published`, slug).
		Scan(&a.Slug, &a.CategorySlug, &title, &body)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ArticleRow{}, ErrArticleNotFound
		}
		return ArticleRow{}, fmt.Errorf("help.repo: get article: %w", err)
	}
	a.Title = decode(title)
	a.Body = decode(body)
	return a, nil
}

func (r *pgxRepository) SearchArticles(ctx context.Context, query string, limit int) ([]ArticleRow, error) {
	like := "%" + query + "%"
	rows, err := r.pool.Query(ctx,
		`SELECT a.slug, c.slug, a.title_translations, a.body_translations
		   FROM help_schema.help_articles a
		   JOIN help_schema.help_categories c ON c.id = a.category_id
		  WHERE a.is_published
		    AND (a.title_translations::text ILIKE $1 OR a.body_translations::text ILIKE $1)
		  ORDER BY a.sort_order, a.id
		  LIMIT $2`, like, limit)
	if err != nil {
		return nil, fmt.Errorf("help.repo: search: %w", err)
	}
	defer rows.Close()
	var out []ArticleRow
	for rows.Next() {
		var a ArticleRow
		var title, body []byte
		if err := rows.Scan(&a.Slug, &a.CategorySlug, &title, &body); err != nil {
			return nil, fmt.Errorf("help.repo: scan search: %w", err)
		}
		a.Title = decode(title)
		a.Body = decode(body)
		out = append(out, a)
	}
	return out, rows.Err()
}

func decode(raw []byte) map[string]string {
	m := map[string]string{}
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &m)
	}
	return m
}
