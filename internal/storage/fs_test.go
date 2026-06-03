package storage

import (
	"bytes"
	"context"
	"io"
	"testing"
)

func TestFSStorage_RoundTrip(t *testing.T) {
	st, err := NewFSStorage(t.TempDir())
	if err != nil {
		t.Fatalf("NewFSStorage: %v", err)
	}
	ctx := context.Background()
	const key = "review/7/abc.jpg"
	if err := st.Put(ctx, key, "image/jpeg", bytes.NewReader([]byte("hello")), 5); err != nil {
		t.Fatalf("Put: %v", err)
	}
	rc, ct, err := st.Get(ctx, key)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	defer rc.Close()
	body, _ := io.ReadAll(rc)
	if string(body) != "hello" {
		t.Errorf("body=%q want hello", body)
	}
	if ct != "image/jpeg" {
		t.Errorf("content-type=%q want image/jpeg", ct)
	}
	if err := st.Delete(ctx, key); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	// Delete is idempotent.
	if err := st.Delete(ctx, key); err != nil {
		t.Errorf("second Delete should be nil, got %v", err)
	}
}

func TestNew_DisabledByDefault(t *testing.T) {
	// A-003: New takes injected Config; a zero Config (Enabled:false) → ErrDisabled.
	if _, err := New(context.Background(), Config{}); err != ErrDisabled {
		t.Errorf("want ErrDisabled, got %v", err)
	}
}
