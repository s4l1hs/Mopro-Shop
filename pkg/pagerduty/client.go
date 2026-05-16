// Package pagerduty provides a thin PagerDuty Events API v2 client.
// Use New(routingKey, endpoint) for production; NewNoop() when routing key is empty.
package pagerduty

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Client sends events to PagerDuty Events API v2.
type Client struct {
	routingKey string
	endpoint   string
	http       *http.Client
}

// New constructs a live Client. routingKey is the PD integration routing key.
// endpoint is the PAGERDUTY_API env var value (e.g. https://events.pagerduty.com/v2/enqueue).
func New(routingKey, endpoint string) *Client {
	return &Client{
		routingKey: routingKey,
		endpoint:   endpoint,
		http:       &http.Client{Timeout: 10 * time.Second},
	}
}

// NewNoop returns a no-op client. All method calls return nil without HTTP activity.
func NewNoop() *Client { return &Client{} }

// Trigger sends a "trigger" event. dedupKey controls PD deduplication.
// Recommended format: "reconcile:{check_name}:{discriminator}"
// Returns nil when routingKey is empty (no-op mode).
func (c *Client) Trigger(ctx context.Context, summary, dedupKey string, details map[string]any) error {
	if c.routingKey == "" {
		return nil
	}
	return c.send(ctx, "trigger", summary, dedupKey, "critical", details)
}

// Resolve closes the open incident for dedupKey. Returns nil in no-op mode.
func (c *Client) Resolve(ctx context.Context, dedupKey string) error {
	if c.routingKey == "" {
		return nil
	}
	return c.send(ctx, "resolve", "", dedupKey, "", nil)
}

func (c *Client) send(ctx context.Context, action, summary, dedupKey, severity string, details map[string]any) error {
	body := map[string]any{
		"routing_key":  c.routingKey,
		"event_action": action,
		"dedup_key":    dedupKey,
		"payload": map[string]any{
			"summary":        summary,
			"severity":       severity,
			"source":         "mopro-fin-svc",
			"custom_details": details,
		},
	}
	b, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("pagerduty: marshal: %w", err)
	}

	// send with 1 retry on non-2xx (simple retry, no exponential backoff).
	const maxAttempts = 2
	var lastErr error
	for attempt := 0; attempt < maxAttempts; attempt++ {
		if attempt > 0 {
			// Brief pause before retry.
			select {
			case <-ctx.Done():
				return fmt.Errorf("pagerduty: %s: context cancelled during retry: %w", action, ctx.Err())
			case <-time.After(100 * time.Millisecond):
			}
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint, bytes.NewReader(b))
		if err != nil {
			return fmt.Errorf("pagerduty: build request: %w", err)
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := c.http.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("pagerduty: %s: %w", action, err)
			continue
		}
		resp.Body.Close()
		if resp.StatusCode/100 != 2 {
			lastErr = fmt.Errorf("pagerduty: %s returned HTTP %d", action, resp.StatusCode)
			continue
		}
		return nil
	}
	return lastErr
}
