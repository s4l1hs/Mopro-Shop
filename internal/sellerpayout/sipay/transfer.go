// Package sipay implements sellerpayout.PspTransferer via Sipay's marketplace transfer API.
// Three modes controlled by SELLERPAYOUT_PSP_MODE env var:
//   - shadow (default): logs the call, returns synthetic transfer_id, no HTTP
//   - mock:             in-process stub; used in unit tests
//   - live:             real Sipay API call
package sipay

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/mopro/platform/internal/sellerpayout"
)

// Mode selects the PSP operation mode.
type Mode string

const (
	ModeLive   Mode = "live"
	ModeShadow Mode = "shadow"
	ModeMock   Mode = "mock"
)

// Client implements sellerpayout.PspTransferer using Sipay's
// /ccpayment/api/member/transfer endpoint.
type Client struct {
	mode       Mode
	baseURL    string
	appKey     string
	appSecret  string
	appID      string
	httpClient *http.Client
	log        *slog.Logger
}

// New constructs a Sipay Client.
// mode is one of "live", "shadow", "mock". Defaults to "shadow" when empty.
func New(mode Mode, baseURL, appKey, appSecret, appID string, log *slog.Logger) *Client {
	if mode == "" {
		mode = ModeShadow
	}
	if log == nil {
		log = slog.Default()
	}
	return &Client{
		mode:       mode,
		baseURL:    strings.TrimRight(baseURL, "/"),
		appKey:     appKey,
		appSecret:  appSecret,
		appID:      appID,
		httpClient: &http.Client{Timeout: 30 * time.Second},
		log:        log,
	}
}

// Transfer initiates a payout to a seller's Sipay member account.
// In shadow mode: logs and returns synthetic transfer_id without any HTTP call.
func (c *Client) Transfer(ctx context.Context, req sellerpayout.TransferRequest) (sellerpayout.TransferResponse, error) {
	if c.mode == ModeShadow {
		synthID := fmt.Sprintf("shadow_synthetic_%d", req.BatchID)
		c.log.InfoContext(ctx, "sipay: shadow transfer",
			"batch_id", req.BatchID,
			"seller_psp_member_id", req.PspMemberID,
			"amount_minor", req.AmountMinor,
			"currency", req.Currency,
			"idempotency_key", req.IdempotencyKey,
			"synthetic_transfer_id", synthID,
		)
		return sellerpayout.TransferResponse{TransferID: synthID, Status: "paid"}, nil
	}
	if c.mode == ModeMock {
		return sellerpayout.TransferResponse{TransferID: fmt.Sprintf("mock_%d", req.BatchID), Status: "paid"}, nil
	}

	// live mode: call Sipay
	amountStr := formatMinorAsTRY(req.AmountMinor)
	body := map[string]any{
		"app_id":     c.appID,
		"app_key":    c.appKey,
		"app_secret": c.appSecret,
		"member_id":  req.PspMemberID,
		"amount":     amountStr,
		"currency":   req.Currency,
		"invoice_id": req.IdempotencyKey,
		"type":       1, // member transfer type
	}
	resp, err := c.post(ctx, "/ccpayment/api/member/transfer", body)
	if err != nil {
		return sellerpayout.TransferResponse{}, fmt.Errorf("sipay: transfer call: %w", err)
	}
	if resp.Status != 1 {
		return sellerpayout.TransferResponse{
			Status:   "failed",
			ErrorMsg: resp.Message,
		}, fmt.Errorf("sipay: transfer rejected: %s", resp.Message)
	}
	return sellerpayout.TransferResponse{
		TransferID: resp.TransferID,
		Status:     "paid",
	}, nil
}

// GetTransferStatus queries Sipay for the status of a previously submitted transfer.
// In shadow / mock mode: always returns paid with the stored transfer_id.
func (c *Client) GetTransferStatus(ctx context.Context, transferID string) (sellerpayout.TransferResponse, error) {
	if c.mode == ModeShadow || c.mode == ModeMock {
		return sellerpayout.TransferResponse{TransferID: transferID, Status: "paid"}, nil
	}

	body := map[string]any{
		"app_id":      c.appID,
		"app_key":     c.appKey,
		"app_secret":  c.appSecret,
		"transfer_id": transferID,
	}
	resp, err := c.post(ctx, "/ccpayment/api/member/transfer/status", body)
	if err != nil {
		return sellerpayout.TransferResponse{}, fmt.Errorf("sipay: get transfer status: %w", err)
	}
	status := "pending"
	if resp.Status == 1 {
		status = "paid"
	} else if resp.Status < 0 {
		status = "failed"
	}
	return sellerpayout.TransferResponse{
		TransferID: resp.TransferID,
		Status:     status,
		ErrorMsg:   resp.Message,
	}, nil
}

// ── internal HTTP helpers ───────────────────────────────────────────────────

type sipayResponse struct {
	Status     int    `json:"status"`
	Message    string `json:"message"`
	TransferID string `json:"transfer_id"`
}

func (c *Client) post(ctx context.Context, path string, body any) (sipayResponse, error) {
	raw, err := json.Marshal(body)
	if err != nil {
		return sipayResponse{}, fmt.Errorf("sipay: marshal request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(raw))
	if err != nil {
		return sipayResponse{}, err
	}
	req.Header.Set("Content-Type", "application/json")

	httpResp, err := c.httpClient.Do(req)
	if err != nil {
		return sipayResponse{}, err
	}
	defer httpResp.Body.Close()

	respBytes, err := io.ReadAll(io.LimitReader(httpResp.Body, 64*1024))
	if err != nil {
		return sipayResponse{}, fmt.Errorf("sipay: read response: %w", err)
	}
	var parsed sipayResponse
	if err := json.Unmarshal(respBytes, &parsed); err != nil {
		return sipayResponse{}, fmt.Errorf("sipay: parse response: %w", err)
	}
	return parsed, nil
}

// formatMinorAsTRY converts integer minor units (kuruş) to a decimal TRY string.
// 100 minor = "1.00", 150 minor = "1.50".
func formatMinorAsTRY(minor int64) string {
	whole := minor / 100
	frac := minor % 100
	return strconv.FormatInt(whole, 10) + "." + fmt.Sprintf("%02d", frac)
}
