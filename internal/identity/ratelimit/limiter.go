// Package ratelimit implements Redis-backed sliding-window rate limiting for OTP operations.
//
// Keys and limits:
//   - rl:otp_req:phone:<hex>   — OTP requests per phone: 3/10min, 5/1hr
//   - rl:otp_req:ip:<addr>     — OTP requests per IP: 10/1hr
//   - rl:otp_verify_fails:<hex> — consecutive verify failures: 10/1hr → 1hr lock
package ratelimit

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// ErrRateLimited is returned when an OTP request rate limit is exceeded.
var ErrRateLimited = errors.New("ratelimit: too many OTP requests")

// ErrLocked is returned when the phone is locked after too many failed verify attempts.
var ErrLocked = errors.New("ratelimit: phone locked after too many failed OTP attempts")

// Limiter enforces rate limits on OTP operations.
type Limiter interface {
	// CheckOTPRequest returns ErrOTPRateLimitExceeded if the phone or IP has exceeded limits.
	CheckOTPRequest(ctx context.Context, phoneHash []byte, clientIP string) error
	// RecordVerifyFailure increments the failure counter for phoneHash.
	// Returns ErrOTPVerifyLocked when the failure count crosses the lock threshold.
	RecordVerifyFailure(ctx context.Context, phoneHash []byte) error
	// ResetVerifyFailures clears the failure counter after a successful verify.
	ResetVerifyFailures(ctx context.Context, phoneHash []byte) error
}

// Lua sliding-window script.
// KEYS[1] = key, ARGV[1] = window_seconds, ARGV[2] = max_count, ARGV[3] = now_unix_ms
// Returns 1 if allowed, 0 if rate-limited.
const slidingWindowLua = `
local key = KEYS[1]
local window_ms = tonumber(ARGV[1]) * 1000
local max = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local cutoff = now - window_ms

redis.call('ZREMRANGEBYSCORE', key, '-inf', cutoff)
local count = redis.call('ZCARD', key)
if count >= max then
    return 0
end
redis.call('ZADD', key, now, now)
redis.call('PEXPIRE', key, window_ms)
return 1
`

// Lua atomic increment for verify-failure lock.
// KEYS[1] = key, ARGV[1] = window_seconds, ARGV[2] = lock_threshold
// Returns current count after increment; caller checks against lock_threshold.
const failCountLua = `
local key = KEYS[1]
local window_sec = tonumber(ARGV[1])
local count = redis.call('INCR', key)
if count == 1 then
    redis.call('EXPIRE', key, window_sec)
end
return count
`

// RedisLimiter is the Redis-backed Limiter implementation.
type RedisLimiter struct {
	rdb *redis.Client
}

// New returns a RedisLimiter using the given Redis client.
func New(rdb *redis.Client) *RedisLimiter {
	return &RedisLimiter{rdb: rdb}
}

func (l *RedisLimiter) CheckOTPRequest(ctx context.Context, phoneHash []byte, clientIP string) error {
	hexPhone := hex.EncodeToString(phoneHash)
	nowMS := time.Now().UnixMilli()

	// Phone limits: 3 per 10 minutes
	if err := l.slidingCheck(ctx, "rl:otp_req:phone:"+hexPhone, 10*60, 3, nowMS); err != nil {
		return err
	}
	// Phone limits: 5 per 1 hour
	if err := l.slidingCheck(ctx, "rl:otp_req:phone:"+hexPhone+":hr", 3600, 5, nowMS); err != nil {
		return err
	}
	// IP limit: 10 per 1 hour
	if clientIP != "" {
		if err := l.slidingCheck(ctx, "rl:otp_req:ip:"+clientIP, 3600, 10, nowMS); err != nil {
			return err
		}
	}
	return nil
}

func (l *RedisLimiter) slidingCheck(ctx context.Context, key string, windowSec, max int64, nowMS int64) error {
	res, err := l.rdb.Eval(ctx, slidingWindowLua,
		[]string{key},
		windowSec, max, nowMS,
	).Int64()
	if err != nil {
		return fmt.Errorf("ratelimit: redis eval: %w", err)
	}
	if res == 0 {
		return ErrRateLimited
	}
	return nil
}

func (l *RedisLimiter) RecordVerifyFailure(ctx context.Context, phoneHash []byte) error {
	key := "rl:otp_verify_fails:" + hex.EncodeToString(phoneHash)
	// 10 failures within 1 hour → lock for 1 hour (window = 3600s)
	count, err := l.rdb.Eval(ctx, failCountLua, []string{key}, 3600, 10).Int64()
	if err != nil {
		return fmt.Errorf("ratelimit: redis eval: %w", err)
	}
	if count >= 10 {
		return ErrLocked
	}
	return nil
}

func (l *RedisLimiter) ResetVerifyFailures(ctx context.Context, phoneHash []byte) error {
	key := "rl:otp_verify_fails:" + hex.EncodeToString(phoneHash)
	return l.rdb.Del(ctx, key).Err()
}
