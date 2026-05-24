// Package idempotency provides HTTP-level idempotency deduplication via Redis.
//
// Middleware intercepts requests with an Idempotency-Key header, locks the key
// in Redis while the handler runs, then caches the response so byte-identical
// replays are returned for repeated keys without re-executing the handler.
package idempotency

import (
	"errors"
	"fmt"
)

// ErrInFlight is returned by Poll when the concurrent request is still running
// after the maximum poll timeout (3 s).
var ErrInFlight = errors.New("idempotency: concurrent request still in flight")

// CachedResponse holds the serialised HTTP response for byte-identical replay.
// encoding/json encodes []byte fields as base64, so Body survives round-trips.
type CachedResponse struct {
	Status      int    `json:"s"`
	ContentType string `json:"ct"`
	Body        []byte `json:"b"`
}

// Key returns the Redis key for a given authenticated user and idempotency-key
// header value.  Format: "idem:{user_id}:{idempotency_key}".
// user_id == 0 is used for unauthenticated endpoints.
func Key(userID int64, idempotencyKey string) string {
	return fmt.Sprintf("idem:%d:%s", userID, idempotencyKey)
}
