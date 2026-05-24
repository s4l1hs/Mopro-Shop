// Package healthcheck provides a minimal Healthchecks.io ping client.
// The Pinger interface abstracts Start/Success/Fail pings so that cron jobs
// can signal liveness to an external monitor without embedding HTTP logic.
// When the configured URL is empty, New returns a no-op implementation.
package healthcheck

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"time"
)

// Pinger abstracts Healthchecks.io UUID-scoped pings.
type Pinger interface {
	// Start signals that the job has begun a run.
	Start(ctx context.Context)
	// Success signals that the job completed successfully.
	Success(ctx context.Context)
	// Fail signals that the job failed. msg is appended to the ping URL as a query parameter.
	Fail(ctx context.Context, msg string)
}

// NewNoop returns a Pinger that silently discards all calls.
func NewNoop() Pinger { return noopPinger{} }

// NewFromUUID constructs a Pinger from a bare healthchecks.io UUID.
// The full ping URL is built as https://hc-ping.com/<uuid>.
// If uuid is empty, a no-op Pinger is returned.
func NewFromUUID(uuid string, timeout time.Duration, log *slog.Logger) Pinger {
	if uuid == "" {
		return NewNoop()
	}
	return New("https://hc-ping.com/"+uuid, timeout, log)
}

// New returns a Pinger that sends HTTP GET requests to baseURL.
// If baseURL is empty, a no-op implementation is returned.
// timeout applies per HTTP call; 5 s is a safe default.
func New(baseURL string, timeout time.Duration, log *slog.Logger) Pinger {
	if baseURL == "" {
		return noopPinger{}
	}
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	if log == nil {
		log = slog.Default()
	}
	return &httpPinger{
		baseURL: baseURL,
		client:  &http.Client{Timeout: timeout},
		log:     log,
	}
}

// ── no-op ─────────────────────────────────────────────────────────────────────

type noopPinger struct{}

func (noopPinger) Start(_ context.Context)          {}
func (noopPinger) Success(_ context.Context)        {}
func (noopPinger) Fail(_ context.Context, _ string) {}

// ── HTTP implementation ───────────────────────────────────────────────────────

type httpPinger struct {
	baseURL string
	client  *http.Client
	log     *slog.Logger
}

func (p *httpPinger) Start(ctx context.Context)   { p.ping(ctx, "/start") }
func (p *httpPinger) Success(ctx context.Context) { p.ping(ctx, "") }
func (p *httpPinger) Fail(ctx context.Context, msg string) {
	suffix := "/fail"
	if msg != "" {
		suffix = fmt.Sprintf("/fail?msg=%s", url.QueryEscape(msg))
	}
	p.ping(ctx, suffix)
}

func (p *httpPinger) ping(ctx context.Context, suffix string) {
	url := p.baseURL + suffix
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		p.log.WarnContext(ctx, "healthcheck: build request", "err", err)
		return
	}
	resp, err := p.client.Do(req)
	if err != nil {
		p.log.WarnContext(ctx, "healthcheck: ping failed", "url", url, "err", err)
		return
	}
	resp.Body.Close()
	if resp.StatusCode >= 300 {
		p.log.WarnContext(ctx, "healthcheck: unexpected status", "url", url, "status", resp.StatusCode)
	}
}
