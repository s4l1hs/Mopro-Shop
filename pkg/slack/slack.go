// Package slack provides a thin Slack Incoming Webhook client.
// Use New(webhookURL) for production; NewNoop() when webhook URL is empty.
package slack

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// Message is the payload sent to a Slack Incoming Webhook.
type Message struct {
	Text string `json:"text"`
}

// Client sends messages to a Slack Incoming Webhook URL.
type Client struct {
	webhookURL string
	http       *http.Client
}

// New constructs a live Client. webhookURL is the full Slack Incoming Webhook URL.
func New(webhookURL string) *Client {
	return &Client{
		webhookURL: webhookURL,
		http:       &http.Client{Timeout: 10 * time.Second},
	}
}

// NewNoop returns a no-op Client. Post always returns nil without any HTTP activity.
func NewNoop() *Client { return &Client{} }

// Post sends msg to the webhook URL. Returns nil in no-op mode (empty webhookURL).
// Retries once on non-2xx to absorb transient Slack 503s.
func (c *Client) Post(ctx context.Context, msg Message) error {
	if c.webhookURL == "" {
		return nil
	}
	b, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("slack: marshal: %w", err)
	}

	const maxAttempts = 2
	var lastErr error
	for attempt := 0; attempt < maxAttempts; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return fmt.Errorf("slack: post: context cancelled during retry: %w", ctx.Err())
			case <-time.After(200 * time.Millisecond):
			}
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.webhookURL, bytes.NewReader(b))
		if err != nil {
			return fmt.Errorf("slack: build request: %w", err)
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := c.http.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("slack: post: %w", err)
			continue
		}
		resp.Body.Close()
		if resp.StatusCode/100 != 2 {
			lastErr = fmt.Errorf("slack: post returned HTTP %d", resp.StatusCode)
			continue
		}
		return nil
	}
	return lastErr
}
