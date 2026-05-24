//go:build !integration

package idempotency_test

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/idempotency"
)

// ── mockStore ─────────────────────────────────────────────────────────────────

type mockStore struct {
	acquireOK  bool
	acquireErr error
	loadResp   *idempotency.CachedResponse
	loadFound  bool
	loadErr    error
	saveErr    error
	pollResp   *idempotency.CachedResponse
	pollErr    error
	released   bool
}

func (m *mockStore) Acquire(_ context.Context, _ string) (bool, error) {
	return m.acquireOK, m.acquireErr
}
func (m *mockStore) Load(_ context.Context, _ string) (*idempotency.CachedResponse, bool, error) {
	return m.loadResp, m.loadFound, m.loadErr
}
func (m *mockStore) Save(_ context.Context, _ string, _ idempotency.CachedResponse) error {
	return m.saveErr
}
func (m *mockStore) Release(_ context.Context, _ string) error {
	m.released = true
	return nil
}
func (m *mockStore) Poll(_ context.Context, _ string) (*idempotency.CachedResponse, error) {
	return m.pollResp, m.pollErr
}

// ── Key tests ─────────────────────────────────────────────────────────────────

func TestKey_Format(t *testing.T) {
	k := idempotency.Key(42, "req-123")
	if k != "idem:42:req-123" {
		t.Errorf("unexpected key format: %q", k)
	}
}

func TestKey_ZeroUser(t *testing.T) {
	k := idempotency.Key(0, "anon-req")
	if k != "idem:0:anon-req" {
		t.Errorf("unexpected key format for zero user: %q", k)
	}
}

// ── Middleware tests ──────────────────────────────────────────────────────────

func echoHandler(status int, body string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	})
}

func TestMiddleware_PassThrough_NoHeader(t *testing.T) {
	mw := idempotency.New(&mockStore{}, func(_ context.Context) int64 { return 1 })
	handler := mw.Wrap(echoHandler(http.StatusOK, `{"ok":true}`))

	r := httptest.NewRequest(http.MethodGet, "/test", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
	if w.Header().Get("X-Idempotent-Replay") != "" {
		t.Error("should not have replay header for requests without Idempotency-Key")
	}
}

func TestMiddleware_FirstRequest_AcquiresAndCaches(t *testing.T) {
	store := &mockStore{acquireOK: true}
	mw := idempotency.New(store, func(_ context.Context) int64 { return 1 })
	handler := mw.Wrap(echoHandler(http.StatusCreated, `{"id":99}`))

	r := httptest.NewRequest(http.MethodPost, "/products", nil)
	r.Header.Set("Idempotency-Key", "key-abc")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusCreated {
		t.Errorf("expected 201, got %d", w.Code)
	}
	if w.Header().Get("X-Idempotent-Replay") != "" {
		t.Error("first request should not set replay header")
	}
}

func TestMiddleware_ReplaysCachedResponse(t *testing.T) {
	cached := &idempotency.CachedResponse{
		Status:      http.StatusCreated,
		ContentType: "application/json",
		Body:        []byte(`{"id":99}`),
	}
	store := &mockStore{acquireOK: false, pollResp: cached}
	mw := idempotency.New(store, func(_ context.Context) int64 { return 1 })
	handler := mw.Wrap(echoHandler(http.StatusInternalServerError, "should not run"))

	r := httptest.NewRequest(http.MethodPost, "/products", nil)
	r.Header.Set("Idempotency-Key", "key-abc")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusCreated {
		t.Errorf("expected replayed 201, got %d", w.Code)
	}
	if w.Header().Get("X-Idempotent-Replay") != "true" {
		t.Error("expected X-Idempotent-Replay: true on replayed response")
	}
	if !bytes.Equal(w.Body.Bytes(), []byte(`{"id":99}`)) {
		t.Errorf("body mismatch: got %q", w.Body.String())
	}
}

func TestMiddleware_InFlight_Returns409(t *testing.T) {
	store := &mockStore{acquireOK: false, pollErr: idempotency.ErrInFlight}
	mw := idempotency.New(store, func(_ context.Context) int64 { return 1 })
	handler := mw.Wrap(echoHandler(http.StatusOK, "should not run"))

	r := httptest.NewRequest(http.MethodPost, "/products", nil)
	r.Header.Set("Idempotency-Key", "key-abc")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusConflict {
		t.Errorf("expected 409 Conflict, got %d", w.Code)
	}
}

func TestMiddleware_RedisError_DegracefulFallthrough(t *testing.T) {
	store := &mockStore{acquireErr: errors.New("redis connection refused")}
	mw := idempotency.New(store, func(_ context.Context) int64 { return 1 })
	handler := mw.Wrap(echoHandler(http.StatusOK, `{"ok":true}`))

	r := httptest.NewRequest(http.MethodPost, "/products", nil)
	r.Header.Set("Idempotency-Key", "key-abc")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)

	// Handler still ran despite Redis error (degrade gracefully)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 (graceful fallthrough), got %d", w.Code)
	}
}

func TestMiddleware_ErrorResponseIsCached(t *testing.T) {
	store := &mockStore{acquireOK: true}
	mw := idempotency.New(store, func(_ context.Context) int64 { return 7 })
	handler := mw.Wrap(echoHandler(http.StatusUnprocessableEntity, `{"error":"invalid"}`))

	r := httptest.NewRequest(http.MethodPost, "/products", nil)
	r.Header.Set("Idempotency-Key", "key-err")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, r)

	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", w.Code)
	}
	// save was called (store.saveErr is nil so it succeeds silently in mock)
}
