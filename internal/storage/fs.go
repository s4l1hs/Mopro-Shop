package storage

import (
	"context"
	"fmt"
	"io"
	"mime"
	"os"
	"path/filepath"
	"strings"
)

// fsStorage writes objects under a base directory. For tests + dev-without-creds
// (and acceptable for staging at low volume per ADR-0004). NewFSStorage is also
// used directly by tests.
type fsStorage struct{ base string }

// NewFSStorage builds a filesystem-backed PhotoStorage rooted at base.
func NewFSStorage(base string) (*fsStorage, error) {
	if base == "" {
		return nil, fmt.Errorf("storage(fs): PHOTO_STORAGE_PATH is empty")
	}
	if err := os.MkdirAll(base, 0o750); err != nil {
		return nil, fmt.Errorf("storage(fs): mkdir base: %w", err)
	}
	return &fsStorage{base: base}, nil
}

func (s *fsStorage) path(key string) string {
	// Keys are server-generated (entity/uid/uuid.ext); reject traversal defensively.
	clean := filepath.Clean("/" + key)
	return filepath.Join(s.base, clean)
}

func (s *fsStorage) Put(_ context.Context, key, _ string, r io.Reader, _ int64) error {
	p := s.path(key)
	if err := os.MkdirAll(filepath.Dir(p), 0o750); err != nil {
		return err
	}
	f, err := os.Create(p)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, r)
	return err
}

func (s *fsStorage) Get(_ context.Context, key string) (io.ReadCloser, string, error) {
	f, err := os.Open(s.path(key))
	if err != nil {
		return nil, "", err
	}
	ct := mime.TypeByExtension(strings.ToLower(filepath.Ext(key)))
	if ct == "" {
		ct = "application/octet-stream"
	}
	return f, ct, nil
}

func (s *fsStorage) Delete(_ context.Context, key string) error {
	err := os.Remove(s.path(key))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func (s *fsStorage) PublicURL(key string) string { return publicURL(key) }
