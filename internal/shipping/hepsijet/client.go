package hepsijet

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

type tokenCache struct {
	mu        sync.RWMutex
	token     string
	expiresAt time.Time
}

func (tc *tokenCache) get() (string, bool) {
	tc.mu.RLock()
	defer tc.mu.RUnlock()
	if tc.token != "" && time.Now().Before(tc.expiresAt) {
		return tc.token, true
	}
	return "", false
}

func (tc *tokenCache) set(token string, ttl time.Duration) {
	tc.mu.Lock()
	tc.token = token
	tc.expiresAt = time.Now().Add(ttl - 30*time.Second)
	tc.mu.Unlock()
}

type client struct {
	baseURL      string
	clientID     string
	clientSecret string
	httpClient   *http.Client
	cache        tokenCache
}

func newClient(baseURL, clientID, clientSecret string) *client {
	return &client{
		baseURL:      baseURL,
		clientID:     clientID,
		clientSecret: clientSecret,
		httpClient:   &http.Client{Timeout: 15 * time.Second},
	}
}

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int    `json:"expires_in"` // seconds
}

func (c *client) bearerToken(ctx context.Context) (string, error) {
	if tok, ok := c.cache.get(); ok {
		return tok, nil
	}
	body := []byte(fmt.Sprintf(
		`{"client_id":%q,"client_secret":%q,"grant_type":"client_credentials"}`,
		c.clientID, c.clientSecret,
	))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/oauth/token", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("hepsijet: oauth: %w", err)
	}
	defer resp.Body.Close()
	var tr tokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tr); err != nil {
		return "", fmt.Errorf("hepsijet: oauth decode: %w", err)
	}
	if tr.AccessToken == "" {
		return "", fmt.Errorf("hepsijet: oauth returned empty token")
	}
	ttl := time.Duration(tr.ExpiresIn) * time.Second
	if ttl <= 0 {
		ttl = 30 * time.Minute
	}
	c.cache.set(tr.AccessToken, ttl)
	return tr.AccessToken, nil
}

func (c *client) do(ctx context.Context, method, path string, in, out any) error {
	tok, err := c.bearerToken(ctx)
	if err != nil {
		return err
	}
	var body *bytes.Reader
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return err
		}
		body = bytes.NewReader(b)
	} else {
		body = bytes.NewReader(nil)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("hepsijet: %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("hepsijet: %s %s status %d", method, path, resp.StatusCode)
	}
	if out != nil {
		return json.NewDecoder(resp.Body).Decode(out)
	}
	return nil
}
