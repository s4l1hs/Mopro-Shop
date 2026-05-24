package idempotency

import (
	"context"
	"errors"
	"net/http"
)

// UserIDExtractor extracts the authenticated user ID from a request context.
// Should return 0 for unauthenticated requests.
type UserIDExtractor func(ctx context.Context) int64

// Middleware wraps HTTP handlers with idempotency deduplication.
type Middleware struct {
	store     Store
	extractID UserIDExtractor
}

// New creates a Middleware that uses store for dedup state and extractID to
// derive the user-scoped cache key.
func New(store Store, extractID UserIDExtractor) *Middleware {
	return &Middleware{store: store, extractID: extractID}
}

// Wrap returns an http.Handler that enforces idempotency for requests that
// carry an Idempotency-Key header.  Requests without the header pass through
// unchanged; the handler still enforces presence for routes that require it.
func (m *Middleware) Wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		idemKey := r.Header.Get("Idempotency-Key")
		if idemKey == "" {
			next.ServeHTTP(w, r)
			return
		}

		userID := m.extractID(r.Context())
		redisKey := Key(userID, idemKey)

		acquired, err := m.store.Acquire(r.Context(), redisKey)
		if err != nil {
			// Redis unavailable: degrade gracefully — run handler without caching.
			next.ServeHTTP(w, r)
			return
		}

		if !acquired {
			m.replayOrWait(w, r, redisKey)
			return
		}

		// We hold the lock: run handler, capture response, then cache it.
		rec := newResponseRecorder(w)
		func() {
			defer func() {
				if p := recover(); p != nil {
					// Release the lock so concurrent pollers are unblocked.
					_ = m.store.Release(context.Background(), redisKey)
					panic(p) //nolint:gocritic // re-panic intentional: propagate to recover at server level
				}
			}()
			next.ServeHTTP(rec, r)
		}()

		resp := CachedResponse{
			Status:      rec.status,
			ContentType: rec.Header().Get("Content-Type"),
			Body:        rec.body.Bytes(),
		}
		// Fire-and-forget: caching failure must not affect the response already sent.
		_ = m.store.Save(r.Context(), redisKey, resp)
	})
}

// replayOrWait handles the case where a key already exists in the store.
func (m *Middleware) replayOrWait(w http.ResponseWriter, r *http.Request, key string) {
	cr, err := m.store.Poll(r.Context(), key)
	if errors.Is(err, ErrInFlight) {
		http.Error(w, `{"error":"idempotent_request_in_progress"}`, http.StatusConflict)
		return
	}
	if err != nil || cr == nil {
		http.Error(w, `{"error":"idempotent_store_unavailable"}`, http.StatusServiceUnavailable)
		return
	}
	if cr.ContentType != "" {
		w.Header().Set("Content-Type", cr.ContentType)
	}
	w.Header().Set("X-Idempotent-Replay", "true")
	w.WriteHeader(cr.Status)
	_, _ = w.Write(cr.Body)
}
