package main

import (
	"context"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/mopro/platform/internal/sitemap"
)

// sitemapSource is anything that can contribute public URLs to the sitemap
// (catalog, seller, help readers). Kept local so the handler doesn't depend on
// each module's concrete reader type.
type sitemapSource interface {
	SitemapURLs(ctx context.Context) ([]sitemap.URL, error)
}

// sitemapStaticURLs are the always-present public pages.
func sitemapStaticURLs() []sitemap.URL {
	return []sitemap.URL{
		{Loc: "/", ChangeFreq: sitemap.ChangeFreqWeekly},
		{Loc: "/help", ChangeFreq: sitemap.ChangeFreqWeekly},
		{Loc: "/categories", ChangeFreq: sitemap.ChangeFreqWeekly},
	}
}

// sitemapCache holds the last-rendered sitemap body + its expiry. Regeneration
// is not real-time-critical; up-to-1h staleness is acceptable (§3.1).
type sitemapCache struct {
	mu      sync.Mutex
	body    []byte
	expires time.Time
}

// handleSitemap serves GET /sitemap.xml, cached for ttl. host is the web origin
// (e.g. https://mopro.shop), prepended to every loc.
func handleSitemap(host string, ttl time.Duration, sources ...sitemapSource) http.HandlerFunc {
	cache := &sitemapCache{}
	return func(w http.ResponseWriter, r *http.Request) {
		cache.mu.Lock()
		if cache.body != nil && time.Now().Before(cache.expires) {
			body := cache.body
			cache.mu.Unlock()
			writeSitemap(w, body)
			return
		}
		cache.mu.Unlock()

		urls := sitemapStaticURLs()
		for _, s := range sources {
			u, err := s.SitemapURLs(r.Context())
			if err != nil {
				slog.Error("sitemap: source failed", "err", err)
				http.Error(w, "internal error", http.StatusInternalServerError)
				return
			}
			urls = append(urls, u...)
		}
		body, err := sitemap.Render(host, urls)
		if err != nil {
			slog.Error("sitemap: render", "err", err)
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		cache.mu.Lock()
		cache.body = body
		cache.expires = time.Now().Add(ttl)
		cache.mu.Unlock()
		writeSitemap(w, body)
	}
}

func writeSitemap(w http.ResponseWriter, body []byte) {
	w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

// handleRobots serves GET /robots.txt.
func handleRobots(host string) http.HandlerFunc {
	body := []byte(sitemap.Robots(host))
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	}
}
