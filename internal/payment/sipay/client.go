// Package sipay implements the payment.Service interface against the Sipay API.
// Sipay is the primary PSP for the TR launch market (PSP_PROVIDER=sipay).
package sipay

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/mopro/platform/internal/payment"
)

func init() {
	payment.RegisterProvider("sipay", func(cfg payment.SipayConfig, repo payment.Repository) payment.Service {
		a, err := NewAdapter(cfg, repo, slog.Default())
		if err != nil {
			log.Fatalf("sipay: adapter init: %v", err)
		}
		return a
	})
}

const (
	connectTimeout = 10 * time.Second
	requestTimeout = 30 * time.Second
	tokenTTL       = 25 * time.Minute

	// maxAttempts is the total attempt count for non-idempotent calls (1 + 1 token-refresh retry).
	maxAttempts = 2
	// maxReadAttempts is the total attempt count for idempotent reads (1 + 3 backoff retries per task spec).
	maxReadAttempts = 3

	// Circuit breaker: open after cbThreshold consecutive failures; retry after cbTimeout.
	cbThreshold = 5
	cbTimeout   = 30 * time.Second
)

// retryBackoffs are sleep durations between successive idempotent-read attempts.
var retryBackoffs = [maxReadAttempts - 1]time.Duration{250 * time.Millisecond, 500 * time.Millisecond}

// ── Circuit breaker ───────────────────────────────────────────────────────────

type cbStateVal int

const (
	cbClosed   cbStateVal = 0
	cbOpen     cbStateVal = 1
	cbHalfOpen cbStateVal = 2
)

type circuitBreaker struct {
	mu        sync.Mutex
	state     cbStateVal
	failures  int
	openedAt  time.Time
	threshold int
	timeout   time.Duration
}

func newCircuitBreaker(threshold int, timeout time.Duration) *circuitBreaker {
	return &circuitBreaker{threshold: threshold, timeout: timeout}
}

// allow returns true if the caller should proceed with the request.
// Transitions Open → HalfOpen when timeout elapses.
func (cb *circuitBreaker) allow() bool {
	cb.mu.Lock()
	defer cb.mu.Unlock()
	switch cb.state {
	case cbOpen:
		if time.Since(cb.openedAt) < cb.timeout {
			return false
		}
		cb.state = cbHalfOpen
		return true
	default:
		return true
	}
}

func (cb *circuitBreaker) recordSuccess() {
	cb.mu.Lock()
	defer cb.mu.Unlock()
	cb.state = cbClosed
	cb.failures = 0
}

func (cb *circuitBreaker) recordFailure() (opened bool) {
	cb.mu.Lock()
	defer cb.mu.Unlock()
	cb.failures++
	if cb.state != cbOpen && cb.failures >= cb.threshold {
		cb.state = cbOpen
		cb.openedAt = time.Now()
		return true
	}
	return false
}

// ── Token cache ───────────────────────────────────────────────────────────────

type tokenCache struct {
	mu        sync.RWMutex
	token     string
	expiresAt time.Time
}

func (tc *tokenCache) get() (string, bool) {
	tc.mu.RLock()
	defer tc.mu.RUnlock()
	if tc.token == "" || time.Now().After(tc.expiresAt) {
		return "", false
	}
	return tc.token, true
}

func (tc *tokenCache) set(token string) {
	tc.mu.Lock()
	defer tc.mu.Unlock()
	tc.token = token
	tc.expiresAt = time.Now().Add(tokenTTL)
}

func (tc *tokenCache) invalidate() {
	tc.mu.Lock()
	defer tc.mu.Unlock()
	tc.token = ""
}

// ── Adapter ───────────────────────────────────────────────────────────────────

// AdapterOption configures optional Adapter behaviour.
type AdapterOption func(*Adapter)

// WithMetrics attaches Prometheus metrics to the Adapter.
// If not provided, all metric recording is a no-op.
func WithMetrics(m *SipayMetrics) AdapterOption {
	return func(a *Adapter) { a.metrics = m }
}

// Adapter implements payment.Service against the Sipay marketplace API.
type Adapter struct {
	cfg     payment.SipayConfig
	repo    payment.Repository
	log     *slog.Logger
	hc      *http.Client
	tokens  tokenCache
	cb      *circuitBreaker
	metrics *SipayMetrics // nil = no-op
}

// NewAdapter constructs a Sipay adapter and validates configuration.
// In GO_ENV=production it enforces that BaseURL points to the real Sipay host
// and that MerchantKey does NOT start with a sandbox prefix.
func NewAdapter(cfg payment.SipayConfig, repo payment.Repository, log *slog.Logger, opts ...AdapterOption) (*Adapter, error) {
	if err := validateConfig(cfg); err != nil {
		return nil, err
	}
	if log == nil {
		log = slog.Default()
	}
	a := &Adapter{
		cfg:  cfg,
		repo: repo,
		log:  log,
		hc: &http.Client{
			Timeout: requestTimeout,
			Transport: &http.Transport{
				DialContext: (&net.Dialer{
					Timeout: connectTimeout,
				}).DialContext,
			},
		},
		cb: newCircuitBreaker(cbThreshold, cbTimeout),
	}
	for _, opt := range opts {
		opt(a)
	}
	return a, nil
}

// validateConfig enforces the production guard on BaseURL and MerchantKey.
func validateConfig(cfg payment.SipayConfig) error {
	if cfg.BaseURL == "" {
		return fmt.Errorf("sipay: SIPAY_BASE_URL is required")
	}
	if cfg.MerchantKey == "" {
		return fmt.Errorf("sipay: SIPAY_MERCHANT_KEY is required")
	}
	if os.Getenv("GO_ENV") == "production" {
		if !strings.Contains(cfg.BaseURL, "provisioning.sipay.com.tr") {
			return fmt.Errorf("sipay: production GO_ENV requires BaseURL to contain provisioning.sipay.com.tr, got %q", cfg.BaseURL)
		}
		if strings.HasPrefix(cfg.MerchantKey, "test_") || strings.HasPrefix(cfg.MerchantKey, "sandbox_") {
			return fmt.Errorf("sipay: production GO_ENV detected sandbox MerchantKey prefix — refusing to start")
		}
	}
	return nil
}

// ── Token management ──────────────────────────────────────────────────────────

type tokenRequest struct {
	AppID     string `json:"app_id"`
	AppSecret string `json:"app_secret"`
}

type tokenResponse struct {
	StatusCode int    `json:"status_code"`
	Message    string `json:"message"`
	Data       struct {
		Token string `json:"token"`
	} `json:"data"`
}

func (a *Adapter) getToken(ctx context.Context) (string, error) {
	if tok, ok := a.tokens.get(); ok {
		return tok, nil
	}
	return a.fetchToken(ctx)
}

func (a *Adapter) fetchToken(ctx context.Context) (string, error) {
	body, err := json.Marshal(tokenRequest{AppID: a.cfg.AppID, AppSecret: a.cfg.AppSecret})
	if err != nil {
		return "", fmt.Errorf("sipay: marshal token req: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		a.cfg.BaseURL+"/ccpayment/api/token", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("sipay: build token req: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	start := time.Now()
	resp, err := a.hc.Do(req)
	elapsed := time.Since(start)
	if err != nil {
		a.log.Info("sipay: token request failed", "latency_ms", elapsed.Milliseconds(), "err", err)
		a.metrics.observe("/ccpayment/api/token", "error", elapsed.Seconds())
		return "", fmt.Errorf("sipay: token HTTP: %w", err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		a.metrics.observe("/ccpayment/api/token", "read_error", elapsed.Seconds())
		return "", fmt.Errorf("sipay: read token body: %w", err)
	}

	statusStr := fmt.Sprintf("%d", resp.StatusCode)
	a.log.Info("sipay: token request", "status", resp.StatusCode, "latency_ms", elapsed.Milliseconds())
	a.metrics.observe("/ccpayment/api/token", statusStr, elapsed.Seconds())

	var tr tokenResponse
	if err := json.Unmarshal(raw, &tr); err != nil {
		return "", fmt.Errorf("sipay: decode token resp: %w", err)
	}
	if tr.StatusCode != 100 || tr.Data.Token == "" {
		return "", fmt.Errorf("sipay: token endpoint returned status %d: %s", tr.StatusCode, tr.Message)
	}

	a.tokens.set(tr.Data.Token)
	return tr.Data.Token, nil
}

// ── Generic request helper ────────────────────────────────────────────────────

// doJSON sends an authenticated POST and decodes the response into dst.
// On HTTP 401 it refreshes the token once (retry-on-401 pattern).
// Not safe for idempotent use with automatic backoff — use doJSONIdempotent for reads.
func (a *Adapter) doJSON(ctx context.Context, path string, payload, dst any) error {
	return a.doJSONWithOpts(ctx, path, payload, dst, false)
}

// attemptResult is the outcome of a single HTTP attempt.
type attemptResult struct {
	raw             []byte
	httpStatus      int
	elapsed         time.Duration
	err             error
	tokenInvalidate bool
}

// attemptDecision is the action doJSONWithOpts should take after inspecting an attemptResult.
type attemptDecision int

const (
	decisionSuccess attemptDecision = iota
	decisionRetry
	decisionFatal
)

// inspect maps an attemptResult to a decision and an error value.
// It updates circuit-breaker state and metrics as a side effect.
func (a *Adapter) inspect(path string, res attemptResult) (attemptDecision, error) {
	if res.tokenInvalidate {
		a.tokens.invalidate()
		return decisionRetry, nil
	}
	if res.err != nil {
		if opened := a.cb.recordFailure(); opened {
			a.metrics.setCBOpen(true)
			a.log.Warn("sipay: circuit breaker opened", "path", path, "failures", cbThreshold)
		}
		return decisionRetry, res.err
	}
	if res.httpStatus < 200 || res.httpStatus >= 300 {
		if opened := a.cb.recordFailure(); opened {
			a.metrics.setCBOpen(true)
			a.log.Warn("sipay: circuit breaker opened", "path", path, "http_status", res.httpStatus)
		}
		return decisionRetry, fmt.Errorf("sipay: %s returned HTTP %d: %s", path, res.httpStatus, res.raw)
	}
	return decisionSuccess, nil
}

// doAttempt executes one HTTP round-trip and returns a structured result.
func (a *Adapter) doAttempt(ctx context.Context, path, tok string, body []byte, attempt int) attemptResult {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, a.cfg.BaseURL+path, bytes.NewReader(body))
	if err != nil {
		return attemptResult{err: fmt.Errorf("sipay: build request: %w", err)}
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+tok)

	start := time.Now()
	resp, err := a.hc.Do(req)
	elapsed := time.Since(start)
	if err != nil {
		a.log.Info("sipay: request error",
			"path", path, "attempt", attempt+1, "latency_ms", elapsed.Milliseconds(), "err", err)
		a.metrics.observe(path, "error", elapsed.Seconds())
		return attemptResult{elapsed: elapsed, err: fmt.Errorf("sipay: %s: %w", path, err)}
	}

	raw, readErr := io.ReadAll(resp.Body)
	resp.Body.Close()
	if readErr != nil {
		a.metrics.observe(path, "read_error", elapsed.Seconds())
		return attemptResult{elapsed: elapsed, err: fmt.Errorf("sipay: read body: %w", readErr)}
	}

	a.log.Info("sipay: request",
		"path", path, "attempt", attempt+1,
		"http_status", resp.StatusCode, "latency_ms", elapsed.Milliseconds())
	a.metrics.observe(path, fmt.Sprintf("%d", resp.StatusCode), elapsed.Seconds())

	return attemptResult{
		raw:             raw,
		httpStatus:      resp.StatusCode,
		elapsed:         elapsed,
		tokenInvalidate: resp.StatusCode == http.StatusUnauthorized && attempt == 0,
	}
}

func (a *Adapter) doJSONWithOpts(ctx context.Context, path string, payload, dst any, idempotent bool) error {
	if !a.cb.allow() {
		a.metrics.observe(path, "circuit_open", 0)
		return fmt.Errorf("sipay: %s: circuit breaker open — Sipay API unavailable", path)
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("sipay: marshal request: %w", err)
	}

	limit := maxAttempts
	if idempotent {
		limit = maxReadAttempts
	}

	var lastErr error
	for attempt := 0; attempt < limit; attempt++ {
		if attempt > 0 && idempotent {
			if err := a.backoffDelay(ctx, attempt-1); err != nil {
				return err
			}
		}

		tok, err := a.getToken(ctx)
		if err != nil {
			return err
		}

		res := a.doAttempt(ctx, path, tok, body, attempt)
		decision, decErr := a.inspect(path, res)
		switch decision {
		case decisionSuccess:
			if err := json.Unmarshal(res.raw, dst); err != nil {
				return fmt.Errorf("sipay: decode response from %s: %w", path, err)
			}
			a.cb.recordSuccess()
			a.metrics.setCBOpen(false)
			return nil
		case decisionRetry:
			lastErr = decErr
			if !idempotent && decErr != nil && !res.tokenInvalidate {
				return lastErr
			}
			continue
		default:
			return decErr
		}
	}
	return lastErr
}

func (a *Adapter) backoffDelay(ctx context.Context, idx int) error {
	if idx < len(retryBackoffs) {
		select {
		case <-time.After(retryBackoffs[idx]):
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}

// ComputeHashKey is defined in hmac.go.
