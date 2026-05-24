package idempotency

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	// inFlightMarker is stored while the first request is executing.
	// Starts with NUL so it can never be mistaken for valid JSON.
	inFlightMarker = "\x00IN_FLIGHT\x00"

	defaultTTL      = 24 * time.Hour
	pollMaxDuration = 3 * time.Second
	pollInitialWait = 50 * time.Millisecond
	pollMaxInterval = 1000 * time.Millisecond
)

// Store manages idempotency state in an external data store.
type Store interface {
	// Acquire atomically marks key as IN_FLIGHT via SETNX.
	// Returns (true, nil) if the caller is the first requester;
	// (false, nil) if a prior entry already exists.
	Acquire(ctx context.Context, key string) (bool, error)

	// Load returns the cached response for key.
	// Returns (resp, true, nil) on a completed entry.
	// Returns (nil, false, nil) when the key is IN_FLIGHT or absent.
	Load(ctx context.Context, key string) (*CachedResponse, bool, error)

	// Save stores resp for key, replacing the IN_FLIGHT marker.
	Save(ctx context.Context, key string, resp CachedResponse) error

	// Release deletes the key (called on handler panic to unblock pollers).
	Release(ctx context.Context, key string) error

	// Poll waits with exponential back-off until key transitions from IN_FLIGHT
	// to a completed response, or until the max duration is exceeded.
	// Returns (nil, nil) if the key disappears (e.g. expired).
	// Returns (nil, ErrInFlight) on timeout.
	Poll(ctx context.Context, key string) (*CachedResponse, error)
}

type redisStore struct {
	rc  *redis.Client
	ttl time.Duration
}

// NewRedisStore returns a Store backed by the given Redis client.
func NewRedisStore(rc *redis.Client) Store {
	return &redisStore{rc: rc, ttl: defaultTTL}
}

func (s *redisStore) Acquire(ctx context.Context, key string) (bool, error) {
	return s.rc.SetNX(ctx, key, inFlightMarker, s.ttl).Result()
}

func (s *redisStore) Load(ctx context.Context, key string) (*CachedResponse, bool, error) {
	raw, err := s.rc.Get(ctx, key).Result()
	if errors.Is(err, redis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, fmt.Errorf("idempotency load: %w", err)
	}
	if raw == inFlightMarker {
		return nil, false, nil
	}
	var cr CachedResponse
	if err := json.Unmarshal([]byte(raw), &cr); err != nil {
		return nil, false, fmt.Errorf("idempotency load unmarshal: %w", err)
	}
	return &cr, true, nil
}

func (s *redisStore) Save(ctx context.Context, key string, resp CachedResponse) error {
	b, err := json.Marshal(resp)
	if err != nil {
		return fmt.Errorf("idempotency save marshal: %w", err)
	}
	return s.rc.Set(ctx, key, b, s.ttl).Err()
}

func (s *redisStore) Release(ctx context.Context, key string) error {
	return s.rc.Del(ctx, key).Err()
}

func (s *redisStore) Poll(ctx context.Context, key string) (*CachedResponse, error) {
	wait := pollInitialWait
	deadline := time.Now().Add(pollMaxDuration)

	for {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(wait):
		}

		cr, found, err := s.Load(ctx, key)
		if err != nil {
			return nil, err
		}
		if found {
			return cr, nil
		}
		if time.Now().After(deadline) {
			return nil, ErrInFlight
		}
		wait = min(wait*2, pollMaxInterval)
	}
}
