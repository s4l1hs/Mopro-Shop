package sitemap

import (
	"strings"
	"testing"
	"time"
)

func TestRender_PrependsHostAndFormatsLastmod(t *testing.T) {
	lm := time.Date(2026, 5, 1, 9, 0, 0, 0, time.UTC)
	body, err := Render("https://mopro.shop/", []URL{
		{Loc: "/products/42", LastMod: &lm, ChangeFreq: ChangeFreqDaily},
		{Loc: "/categories/5", ChangeFreq: ChangeFreqWeekly}, // no lastmod
	})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	s := string(body)
	if !strings.Contains(s, "<?xml") || !strings.Contains(s, "sitemaps.org/schemas/sitemap/0.9") {
		t.Errorf("missing xml header/namespace: %s", s)
	}
	if !strings.Contains(s, "<loc>https://mopro.shop/products/42</loc>") {
		t.Errorf("host not prepended / loc wrong: %s", s)
	}
	if !strings.Contains(s, "<lastmod>2026-05-01</lastmod>") {
		t.Errorf("lastmod not date-formatted: %s", s)
	}
	if !strings.Contains(s, "<changefreq>daily</changefreq>") {
		t.Errorf("changefreq missing: %s", s)
	}
	// The category entry has no lastmod element.
	if strings.Count(s, "<lastmod>") != 1 {
		t.Errorf("expected exactly 1 lastmod (product only): %s", s)
	}
	// Trailing slash on host is trimmed (no double slash).
	if strings.Contains(s, "shop//") {
		t.Errorf("double slash from untrimmed host: %s", s)
	}
}

func TestRobots_AllowsCrawlersDisallowsAuthGated(t *testing.T) {
	out := Robots("https://mopro.shop")
	if !strings.HasPrefix(out, "User-agent: *\nAllow: /\n") {
		t.Errorf("missing allow-all preamble: %q", out)
	}
	for _, p := range []string{"/account", "/orders", "/returns", "/seller", "/checkout", "/wallet", "/profile", "/auth"} {
		if !strings.Contains(out, "Disallow: "+p+"\n") {
			t.Errorf("missing Disallow %s in:\n%s", p, out)
		}
	}
	if !strings.Contains(out, "Sitemap: https://mopro.shop/sitemap.xml\n") {
		t.Errorf("missing sitemap pointer: %q", out)
	}
}
