// Package sitemap renders an XML sitemap (sitemaps.org/0.9) and the robots.txt
// body. It holds only value types + rendering — no DB access, no cross-schema
// queries. Each owning module (catalog, seller, help) builds its own []URL
// (with module-correct paths) via a narrow SitemapReader; cmd/core-svc
// aggregates them and prepends the web host here.
package sitemap

import (
	"encoding/xml"
	"strings"
	"time"
)

// Change frequencies (sitemaps.org changefreq values).
const (
	ChangeFreqDaily  = "daily"
	ChangeFreqWeekly = "weekly"
)

// URL is one sitemap entry. Loc is a host-relative path (e.g. "/products/42");
// the host is prepended at render time. LastMod is optional (omitted when nil).
type URL struct {
	Loc        string
	LastMod    *time.Time
	ChangeFreq string
}

// xmlURL is the marshalled form (sitemaps.org schema).
type xmlURL struct {
	Loc        string `xml:"loc"`
	LastMod    string `xml:"lastmod,omitempty"`
	ChangeFreq string `xml:"changefreq,omitempty"`
}

type xmlURLSet struct {
	XMLName xml.Name `xml:"urlset"`
	Xmlns   string   `xml:"xmlns,attr"`
	URLs    []xmlURL `xml:"url"`
}

// Render builds the XML sitemap document for the given host (e.g.
// "https://mopro.shop", no trailing slash). lastmod is formatted as a date
// (YYYY-MM-DD) per common sitemap practice.
func Render(host string, urls []URL) ([]byte, error) {
	host = strings.TrimRight(host, "/")
	set := xmlURLSet{Xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9"}
	for _, u := range urls {
		x := xmlURL{Loc: host + u.Loc, ChangeFreq: u.ChangeFreq}
		if u.LastMod != nil {
			x.LastMod = u.LastMod.UTC().Format("2006-01-02")
		}
		set.URLs = append(set.URLs, x)
	}
	body, err := xml.MarshalIndent(set, "", "  ")
	if err != nil {
		return nil, err
	}
	return append([]byte(xml.Header), body...), nil
}

// Robots returns the robots.txt body: crawlers allowed, auth-gated route
// prefixes disallowed, sitemap pointer at the given host.
func Robots(host string) string {
	host = strings.TrimRight(host, "/")
	var b strings.Builder
	b.WriteString("User-agent: *\n")
	b.WriteString("Allow: /\n")
	for _, p := range []string{
		"/account", "/orders", "/returns", "/seller",
		"/checkout", "/wallet", "/profile", "/auth",
	} {
		b.WriteString("Disallow: " + p + "\n")
	}
	b.WriteString("\nSitemap: " + host + "/sitemap.xml\n")
	return b.String()
}
