package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mopro/platform/internal/sitemap"
)

type stubSitemapSource struct {
	urls  []sitemap.URL
	calls int32
}

func (s *stubSitemapSource) SitemapURLs(_ context.Context) ([]sitemap.URL, error) {
	atomic.AddInt32(&s.calls, 1)
	return s.urls, nil
}

func TestHandleSitemap_ShapeCacheAndExclusions(t *testing.T) {
	src := &stubSitemapSource{urls: []sitemap.URL{
		{Loc: "/products/1", ChangeFreq: sitemap.ChangeFreqDaily},
		{Loc: "/sellers/acme-store", ChangeFreq: sitemap.ChangeFreqWeekly},
	}}
	h := handleSitemap("https://mopro.shop", time.Hour, src)

	rec := httptest.NewRecorder()
	h(rec, httptest.NewRequest(http.MethodGet, "/sitemap.xml", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/xml") {
		t.Errorf("content-type: want application/xml, got %q", ct)
	}
	if cc := rec.Header().Get("Cache-Control"); !strings.Contains(cc, "max-age=3600") {
		t.Errorf("cache-control: want max-age=3600, got %q", cc)
	}
	body := rec.Body.String()
	// Static + source URLs present, host-prefixed.
	for _, want := range []string{
		"https://mopro.shop/", "https://mopro.shop/help", "https://mopro.shop/categories",
		"https://mopro.shop/products/1", "https://mopro.shop/sellers/acme-store",
	} {
		if !strings.Contains(body, "<loc>"+want+"</loc>") {
			t.Errorf("missing loc %q in sitemap", want)
		}
	}
	// Auth-gated routes never appear.
	for _, bad := range []string{"/account", "/orders", "/returns", "/checkout", "/wallet", "/seller/returns", "/auth"} {
		if strings.Contains(body, "<loc>https://mopro.shop"+bad) {
			t.Errorf("auth-gated route leaked into sitemap: %s", bad)
		}
	}

	// Second request within TTL is served from cache (source not re-queried).
	rec2 := httptest.NewRecorder()
	h(rec2, httptest.NewRequest(http.MethodGet, "/sitemap.xml", nil))
	if rec2.Code != http.StatusOK {
		t.Fatalf("second call status: %d", rec2.Code)
	}
	if got := atomic.LoadInt32(&src.calls); got != 1 {
		t.Errorf("source queried %d times; want 1 (cached)", got)
	}
}

func TestHandleRobots_Content(t *testing.T) {
	rec := httptest.NewRecorder()
	handleRobots("https://mopro.shop")(rec, httptest.NewRequest(http.MethodGet, "/robots.txt", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status: %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Errorf("content-type: want text/plain, got %q", ct)
	}
	body := rec.Body.String()
	if !strings.Contains(body, "Disallow: /account") || !strings.Contains(body, "Sitemap: https://mopro.shop/sitemap.xml") {
		t.Errorf("robots body unexpected:\n%s", body)
	}
}
