// Package sipay implements the payment.Service interface against the Sipay API.
// Sipay is the primary PSP for the TR launch market (PSP_PROVIDER=sipay).
package sipay

import (
	"bytes"
	"context"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"log/slog"
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
	tokenTTL       = 25 * time.Minute // Sipay token lifetime minus 5-min buffer
	maxRetries     = 2
	requestTimeout = 30 * time.Second
)

// tokenCache holds the current bearer token with its expiry.
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

// Adapter implements payment.Service against the Sipay marketplace API.
type Adapter struct {
	cfg    payment.SipayConfig
	repo   payment.Repository
	log    *slog.Logger
	hc     *http.Client
	tokens tokenCache
}

// NewAdapter constructs a Sipay adapter and validates configuration.
// D2: in production mode it enforces that BaseURL points to the real Sipay host
// and that MerchantKey does NOT start with a sandbox prefix.
func NewAdapter(cfg payment.SipayConfig, repo payment.Repository, log *slog.Logger) (*Adapter, error) {
	if err := validateConfig(cfg); err != nil {
		return nil, err
	}
	if log == nil {
		log = slog.Default()
	}
	return &Adapter{
		cfg:  cfg,
		repo: repo,
		log:  log,
		hc:   &http.Client{Timeout: requestTimeout},
	}, nil
}

// validateConfig enforces D2: production guard on BaseURL and MerchantKey.
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

// --- Token management ---

// tokenRequest is the body sent to Sipay's /ccpayment/api/token endpoint.
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

// getToken returns a cached token or fetches a fresh one.
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

	resp, err := a.hc.Do(req)
	if err != nil {
		return "", fmt.Errorf("sipay: token HTTP: %w", err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("sipay: read token body: %w", err)
	}

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

// --- Generic request helper ---

// doJSON sends an authenticated POST and decodes the response into dst.
// On HTTP 401 it refreshes the token once (retry-on-401 pattern).
func (a *Adapter) doJSON(ctx context.Context, path string, payload, dst any) error {
	for attempt := 0; attempt < maxRetries; attempt++ {
		tok, err := a.getToken(ctx)
		if err != nil {
			return err
		}

		body, err := json.Marshal(payload)
		if err != nil {
			return fmt.Errorf("sipay: marshal request: %w", err)
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodPost,
			a.cfg.BaseURL+path, bytes.NewReader(body))
		if err != nil {
			return fmt.Errorf("sipay: build request: %w", err)
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+tok)

		resp, err := a.hc.Do(req)
		if err != nil {
			return fmt.Errorf("sipay: %s: %w", path, err)
		}
		raw, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			return fmt.Errorf("sipay: read body: %w", readErr)
		}

		if resp.StatusCode == http.StatusUnauthorized && attempt == 0 {
			// Force token refresh on the next iteration.
			a.tokens.mu.Lock()
			a.tokens.token = ""
			a.tokens.mu.Unlock()
			continue
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return fmt.Errorf("sipay: %s returned HTTP %d: %s", path, resp.StatusCode, raw)
		}
		if err := json.Unmarshal(raw, dst); err != nil {
			return fmt.Errorf("sipay: decode response from %s: %w", path, err)
		}
		return nil
	}
	return fmt.Errorf("sipay: %s: exhausted retries", path)
}

// --- HMAC signature helper used by webhook handler ---

// ComputeHashKey produces the Sipay webhook HMAC-SHA512 signature.
// hash_key = base64( SHA512( merchant_key + status_code + invoice_id + total_amount + currency_code ) )
func ComputeHashKey(merchantKey, statusCode, invoiceID, totalAmount, currencyCode string) string {
	raw := merchantKey + statusCode + invoiceID + totalAmount + currencyCode
	sum := sha512.Sum512([]byte(raw))
	return base64.StdEncoding.EncodeToString(sum[:])
}
