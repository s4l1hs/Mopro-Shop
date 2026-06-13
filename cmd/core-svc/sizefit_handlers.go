package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/seller"
	"github.com/mopro/platform/internal/sizefinder"
)

// toSellerChart maps a resolved seller.SizeChart to the value object sizefinder
// consumes (passed over the internal recommend body — jobs-svc never reads
// seller_schema, §5).
func toSellerChart(c seller.SizeChart) *sizefinder.SellerChart {
	rows := make([]sizefinder.ChartRow, len(c.Rows))
	for i, r := range c.Rows {
		rows[i] = sizefinder.ChartRow{
			GarmentType: sizefinder.GarmentType(c.GarmentType),
			SizeLabel:   r.SizeLabel,
			SortRank:    r.SortRank,
			Measurement: r.Measurement,
			MinMM:       r.MinMM,
			MaxMM:       r.MaxMM,
		}
	}
	return &sizefinder.SellerChart{
		GarmentType: sizefinder.GarmentType(c.GarmentType),
		Gender:      c.Gender,
		Rows:        rows,
	}
}

// Size-fit consumer API (docs/internal/size-fit.md). The sizefinder module is
// constitutionally jobs-svc, so these handlers are thin auth-gated proxies over
// the FIRST core→jobs §3.4 synchronous HTTP path: requireAuth resolves the
// user, core resolves the product title in-process (catalog.Service, §3.1),
// and the call crosses to jobs-svc on mopro-net with the internal token.
// Measurements transit core only in memory — they are stored (encrypted, §6)
// solely by the sizefinder repository.

type sizefitClient struct {
	base  string
	token string
	http  *http.Client
}

func newSizefitClient() *sizefitClient {
	base := os.Getenv("JOBS_SVC_URL")
	if base == "" {
		base = "http://jobs-svc:8080"
	}
	return &sizefitClient{
		base:  base,
		token: os.Getenv("ADMIN_INTERNAL_TOKEN"),
		http:  &http.Client{Timeout: 5 * time.Second},
	}
}

// do proxies one JSON request to jobs-svc and returns (status, body).
func (c *sizefitClient) do(method, path string, payload any) (int, []byte, error) {
	var body io.Reader
	if payload != nil {
		b, err := json.Marshal(payload)
		if err != nil {
			return 0, nil, err
		}
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, c.base+path, body)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return resp.StatusCode, b, err
}

// handleGetFitProfile serves GET /me/fit-profile. A user without a profile gets
// 200 {exists:false} (simpler client state than a 404).
func handleGetFitProfile(client *sizefitClient) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		status, body, err := client.do(http.MethodGet,
			fmt.Sprintf("/internal/sizefit/profile?user_id=%d", userID), nil)
		if err != nil {
			slog.Error("sizefit: jobs-svc get profile", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		switch status {
		case http.StatusOK:
			var p sizefinder.FitProfile
			if err := json.Unmarshal(body, &p); err != nil {
				jsonError(w, "internal error", http.StatusInternalServerError)
				return
			}
			jsonOK(w, http.StatusOK, map[string]any{"exists": true, "profile": p})
		case http.StatusNotFound:
			jsonOK(w, http.StatusOK, map[string]any{"exists": false})
		default:
			slog.Error("sizefit: jobs-svc get profile status", "status", status)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}

// handlePutFitProfile serves PUT /me/fit-profile (idempotent upsert).
func handlePutFitProfile(client *sizefitClient) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		var p sizefinder.FitProfile
		if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
			jsonError(w, "invalid JSON", http.StatusBadRequest)
			return
		}
		p.UserID = userID // server-authoritative; never trust a body user id
		status, _, err := client.do(http.MethodPut, "/internal/sizefit/profile", p)
		if err != nil {
			slog.Error("sizefit: jobs-svc put profile", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		switch status {
		case http.StatusNoContent:
			w.WriteHeader(http.StatusNoContent)
		case http.StatusUnprocessableEntity:
			jsonError(w, "invalid measurement", http.StatusUnprocessableEntity)
		default:
			slog.Error("sizefit: jobs-svc put profile status", "status", status)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}

// handleSizeRecommendation serves GET /products/{id}/size-recommendation.
// Core resolves the product title (server-authoritative) then asks jobs-svc.
func handleSizeRecommendation(client *sizefitClient, svc catalog.Service, sellerSvc seller.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		_, _, translations, err := svc.GetByID(r.Context(), id)
		if err != nil {
			jsonError(w, "product not found", http.StatusNotFound)
			return
		}
		title, _ := resolveTranslation(translations, parseLocale(r, defaultLocale), defaultLocale)
		// Precedence resolution (§5-safe, in-process): a seller chart attached to
		// this product wins over the standard baseline. Core reads seller_schema
		// and hands jobs-svc a value object; jobs-svc never touches seller_schema.
		payload := map[string]any{"user_id": userID, "title": title}
		if chart, ok, cerr := sellerSvc.SizeChartForProduct(r.Context(), id); cerr == nil && ok {
			payload["seller_chart"] = toSellerChart(chart)
		} else if cerr != nil {
			slog.Error("sizefit: resolve seller chart", "product_id", id, "err", cerr)
		}
		status, body, err := client.do(http.MethodPost, "/internal/sizefit/recommend", payload)
		if err != nil || status != http.StatusOK {
			slog.Error("sizefit: jobs-svc recommend", "err", err, "status", status)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		var rec sizefinder.Recommendation
		if err := json.Unmarshal(body, &rec); err != nil {
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, rec)
	}
}
