package surat

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
	baseURL    string
	username   string
	password   string
	httpClient *http.Client
	cache      tokenCache
}

func newClient(baseURL, username, password string) *client {
	return &client{
		baseURL:    baseURL,
		username:   username,
		password:   password,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}
}

type authRequest struct {
	Username string `json:"Username"`
	Password string `json:"Password"`
}

type authResponse struct {
	Data struct {
		Token     string `json:"Token"`
		ExpiresIn int    `json:"ExpiresIn"` // seconds
	} `json:"Data"`
	Status int `json:"Status"`
}

func (c *client) bearerToken(ctx context.Context) (string, error) {
	if tok, ok := c.cache.get(); ok {
		return tok, nil
	}
	body, _ := json.Marshal(authRequest{Username: c.username, Password: c.password})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/api/v1/auth/login", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("surat: auth: %w", err)
	}
	defer resp.Body.Close()
	var ar authResponse
	if err := json.NewDecoder(resp.Body).Decode(&ar); err != nil {
		return "", fmt.Errorf("surat: auth decode: %w", err)
	}
	if ar.Status != 200 || ar.Data.Token == "" {
		return "", fmt.Errorf("surat: auth failed (status %d)", ar.Status)
	}
	ttl := time.Duration(ar.Data.ExpiresIn) * time.Second
	if ttl <= 0 {
		ttl = 30 * time.Minute
	}
	c.cache.set(ar.Data.Token, ttl)
	return ar.Data.Token, nil
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
		return fmt.Errorf("surat: %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("surat: %s %s status %d", method, path, resp.StatusCode)
	}
	if out != nil {
		return json.NewDecoder(resp.Body).Decode(out)
	}
	return nil
}
