// Package storage is the app's object-storage boundary for user media uploads
// (review + return photos). S3-compatible (Backblaze B2 in prod, MinIO in dev/CI)
// per ADR-0004, with a filesystem impl for tests + dev-without-creds. Gated by
// STORAGE_ENABLED (default false) until an app bucket is provisioned.
package storage

import (
	"context"
	"errors"
	"io"
	"os"

	"github.com/mopro/platform/pkg/mediaurl"
)

// ErrDisabled is returned by New when STORAGE_ENABLED is not "true".
var ErrDisabled = errors.New("storage: disabled (set STORAGE_ENABLED=true once a bucket is provisioned)")

// PhotoStorage is the object-storage contract. Keys are bucket-relative, opaque,
// immutable (e.g. "review/42/<uuid>.jpg").
type PhotoStorage interface {
	Put(ctx context.Context, key, contentType string, r io.Reader, size int64) error
	Get(ctx context.Context, key string) (io.ReadCloser, string, error)
	Delete(ctx context.Context, key string) error
	// PublicURL returns the externally-accessible (CDN-fronted) URL for a key.
	PublicURL(key string) string
}

// Enabled reports whether media uploads are turned on (an app bucket exists).
func Enabled() bool { return os.Getenv("STORAGE_ENABLED") == "true" }

// New builds the configured PhotoStorage. STORAGE_BACKEND selects the impl:
// "fs" (filesystem, dev/test) or anything else → S3 (default). Returns
// ErrDisabled when STORAGE_ENABLED != "true".
func New(ctx context.Context) (PhotoStorage, error) {
	if !Enabled() {
		return nil, ErrDisabled
	}
	if os.Getenv("STORAGE_BACKEND") == "fs" {
		return NewFSStorage(os.Getenv("PHOTO_STORAGE_PATH"))
	}
	return newS3Storage(ctx)
}

// publicURL is the shared key→URL resolution (CDN-fronted via CDN_BASE_URL),
// matching how product/seller image keys resolve.
func publicURL(key string) string { return mediaurl.CDNUrl(key) }
