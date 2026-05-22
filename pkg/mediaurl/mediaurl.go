// Package mediaurl resolves raw object-storage keys to CDN-served HTTPS URLs.
// Core-svc is the sole consumer; fin-svc MUST NOT import this package.
package mediaurl

import "os"

// CDNUrl converts a raw storage key (e.g. "media/products/abc.jpg") to a
// CDN-served URL by prepending CDN_BASE_URL from the environment.
// Returns the key unchanged when CDN_BASE_URL is unset (test / dev mode).
func CDNUrl(key string) string {
	if key == "" {
		return ""
	}
	base := os.Getenv("CDN_BASE_URL")
	if base == "" {
		return key
	}
	return base + "/" + key
}
