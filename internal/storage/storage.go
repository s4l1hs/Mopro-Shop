// Package storage is the app's object-storage boundary for user media uploads
// (review + return photos). S3-compatible (Backblaze B2 in prod, MinIO in dev/CI)
// per ADR-0004, with a filesystem impl for tests + dev-without-creds. Gated by
// STORAGE_ENABLED (default false) until an app bucket is provisioned.
package storage

import (
	"context"
	"errors"
	"io"

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

// Config is the storage configuration (A-003: injected; was os.Getenv in New/newS3Storage).
// The env-read lives at the binary entry (cmd/core-svc/main.go); tests build Config directly.
type Config struct {
	Enabled   bool   // STORAGE_ENABLED == "true"
	Backend   string // STORAGE_BACKEND ("fs" → filesystem; anything else → S3)
	FSPath    string // PHOTO_STORAGE_PATH (fs backend)
	Endpoint  string // STORAGE_ENDPOINT (S3-compatible)
	Bucket    string // STORAGE_BUCKET
	Region    string // STORAGE_REGION (default us-east-1 when empty)
	AccessKey string // STORAGE_ACCESS_KEY
	SecretKey string // STORAGE_SECRET_KEY
}

// New builds the configured PhotoStorage. cfg.Backend=="fs" → filesystem (dev/test);
// anything else → S3 (default). Returns ErrDisabled when cfg.Enabled is false.
func New(ctx context.Context, cfg Config) (PhotoStorage, error) {
	if !cfg.Enabled {
		return nil, ErrDisabled
	}
	if cfg.Backend == "fs" {
		return NewFSStorage(cfg.FSPath)
	}
	return newS3Storage(ctx, cfg)
}

// publicURL is the shared key→URL resolution (CDN-fronted via CDN_BASE_URL),
// matching how product/seller image keys resolve.
func publicURL(key string) string { return mediaurl.CDNUrl(key) }
