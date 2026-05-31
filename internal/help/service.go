package help

import (
	"context"
	"errors"
	"log/slog"
	"strings"
)

// ErrArticleNotFound is returned when a slug has no published article.
var ErrArticleNotFound = errors.New("help: article not found")

const (
	searchCap      = 20
	snippetLen     = 150
	fallbackLocale = "tr" // launch market; second after the requested locale
)

type service struct {
	repo Repository
	log  *slog.Logger
}

// NewService builds the help Service.
func NewService(repo Repository, log *slog.Logger) Service {
	if log == nil {
		log = slog.Default()
	}
	return &service{repo: repo, log: log}
}

// resolveLocale picks a translation: requested → tr → en → first available.
// Logs a counter-friendly warning when the requested locale is missing so the
// translation-coverage Backlog item has a real number behind it.
func (s *service) resolve(m map[string]string, locale, slug string) string {
	lang := localeLang(locale)
	if v, ok := m[lang]; ok && v != "" {
		return v
	}
	s.log.Warn("help: missing translation", "locale", lang, "slug", slug)
	for _, fb := range []string{fallbackLocale, "en"} {
		if v, ok := m[fb]; ok && v != "" {
			return v
		}
	}
	for _, v := range m {
		if v != "" {
			return v
		}
	}
	return ""
}

// localeLang reduces "de-DE" / "tr_TR" to the bare language code "de"/"tr".
func localeLang(locale string) string {
	l := strings.ToLower(strings.TrimSpace(locale))
	for _, sep := range []string{"-", "_"} {
		if i := strings.Index(l, sep); i > 0 {
			return l[:i]
		}
	}
	if l == "" {
		return fallbackLocale
	}
	return l
}

func (s *service) ListCategories(ctx context.Context, locale string) ([]Category, error) {
	rows, err := s.repo.ListCategories(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]Category, 0, len(rows))
	for _, r := range rows {
		out = append(out, Category{
			Slug:         r.Slug,
			Title:        s.resolve(r.Title, locale, r.Slug),
			IconName:     r.IconName,
			ArticleCount: r.ArticleCount,
		})
	}
	return out, nil
}

func (s *service) ListArticles(ctx context.Context, categorySlug, locale string) ([]Article, error) {
	rows, err := s.repo.ListArticles(ctx, categorySlug)
	if err != nil {
		return nil, err
	}
	out := make([]Article, 0, len(rows))
	for _, r := range rows {
		out = append(out, Article{Slug: r.Slug, Title: s.resolve(r.Title, locale, r.Slug)})
	}
	return out, nil
}

func (s *service) GetArticle(ctx context.Context, slug, locale string) (Article, error) {
	r, err := s.repo.GetArticle(ctx, slug)
	if err != nil {
		return Article{}, err
	}
	return Article{
		Slug:     r.Slug,
		Title:    s.resolve(r.Title, locale, r.Slug),
		Body:     s.resolve(r.Body, locale, r.Slug),
		Category: r.CategorySlug,
	}, nil
}

func (s *service) Search(ctx context.Context, query, locale string) ([]SearchResult, error) {
	q := strings.TrimSpace(query)
	if q == "" {
		return []SearchResult{}, nil
	}
	rows, err := s.repo.SearchArticles(ctx, q, searchCap)
	if err != nil {
		return nil, err
	}
	out := make([]SearchResult, 0, len(rows))
	for _, r := range rows {
		out = append(out, SearchResult{
			Slug:         r.Slug,
			Title:        s.resolve(r.Title, locale, r.Slug),
			Snippet:      snippet(s.resolve(r.Body, locale, r.Slug), q),
			CategorySlug: r.CategorySlug,
		})
	}
	return out, nil
}

// snippet extracts ~snippetLen chars around the first match of q in body and
// wraps case-insensitive matches of q with ** markers for client-side bolding.
func snippet(body, q string) string {
	plain := strings.ReplaceAll(body, "#", "")
	plain = strings.Join(strings.Fields(plain), " ")
	lower := strings.ToLower(plain)
	idx := strings.Index(lower, strings.ToLower(q))
	start := 0
	if idx > 40 {
		start = idx - 40
	}
	end := start + snippetLen
	if end > len(plain) {
		end = len(plain)
	}
	// Avoid slicing mid-rune: back off to a rune boundary.
	for start > 0 && !utf8Start(plain[start]) {
		start--
	}
	for end < len(plain) && !utf8Start(plain[end]) {
		end++
	}
	frag := plain[start:end]
	return mark(frag, q)
}

func utf8Start(b byte) bool { return b&0xC0 != 0x80 }

// mark wraps case-insensitive occurrences of q in s with ** ** .
func mark(s, q string) string {
	lowerS, lowerQ := strings.ToLower(s), strings.ToLower(q)
	var b strings.Builder
	for {
		i := strings.Index(lowerS, lowerQ)
		if i < 0 {
			b.WriteString(s)
			break
		}
		b.WriteString(s[:i])
		b.WriteString("**")
		b.WriteString(s[i : i+len(q)])
		b.WriteString("**")
		s = s[i+len(q):]
		lowerS = lowerS[i+len(q):]
	}
	return b.String()
}
