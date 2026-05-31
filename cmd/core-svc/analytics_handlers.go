package main

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/mopro/platform/internal/analytics"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
)

// ── POST /analytics/events ─────────────────────────────────────────────────────
// OptionalAuth: works for guest sessions. Consent is enforced server-side inside
// the service; this endpoint returns 204 on any well-formed batch regardless of
// whether events were ultimately stored (§3.3 — the client never learns).

func handleIngestEvents(svc analytics.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			SessionID string `json:"sessionId"`
			Events    []struct {
				Type     string         `json:"type"`
				Payload  map[string]any `json:"payload"`
				ClientTs time.Time      `json:"clientTs"`
			} `json:"events"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		batch := analytics.IngestBatch{SessionID: body.SessionID}
		if uid := middleware.UserIDFromCtx(r.Context()); uid > 0 {
			batch.UserID = &uid
		}
		for _, e := range body.Events {
			ts := e.ClientTs
			if ts.IsZero() {
				ts = time.Now().UTC()
			}
			batch.Events = append(batch.Events, analytics.Event{
				Type: e.Type, Payload: e.Payload, ClientTs: ts,
			})
		}
		err := svc.Ingest(r.Context(), batch)
		switch {
		case err == nil:
			w.WriteHeader(http.StatusNoContent)
		case errors.Is(err, analytics.ErrBatchTooLarge):
			jsonError(w, "batch too large", http.StatusRequestEntityTooLarge)
		case errors.Is(err, analytics.ErrUnknownEventType),
			errors.Is(err, analytics.ErrMissingPayloadField),
			errors.Is(err, analytics.ErrInvalidSession),
			errors.Is(err, analytics.ErrEmptyBatch):
			jsonError(w, err.Error(), http.StatusBadRequest)
		default:
			slog.Error("analytics: ingest", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}

// ── POST /analytics/sessions/identify ──────────────────────────────────────────
// RequireAuth. Binds the guest session to the user + backfills projections.

func handleIdentifySession(svc analytics.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			SessionID string `json:"sessionId"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		if err := svc.IdentifySession(r.Context(), body.SessionID, userID); err != nil {
			if errors.Is(err, analytics.ErrInvalidSession) {
				jsonError(w, "invalid session id", http.StatusBadRequest)
				return
			}
			slog.Error("analytics: identify", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// ── GET /me/consent ─────────────────────────────────────────────────────────────

func handleGetConsent(svc analytics.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		c, err := svc.GetConsent(r.Context(), userID)
		if err != nil {
			slog.Error("analytics: get consent", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, c)
	}
}

// ── PUT /me/consent ─────────────────────────────────────────────────────────────

func handleSetConsent(svc analytics.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			AnalyticsEnabled bool `json:"analyticsEnabled"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		c, err := svc.SetConsent(r.Context(), userID, body.AnalyticsEnabled)
		if err != nil {
			slog.Error("analytics: set consent", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, c)
	}
}

// ── DELETE /me/analytics-data ───────────────────────────────────────────────────
// RTBF (Decision 5). Erases the user's analytics rows; leaves consent intact.

func handleDeleteAnalyticsData(svc analytics.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		if err := svc.DeleteUserData(r.Context(), userID); err != nil {
			slog.Error("analytics: erase user data", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// ── GET /me/recently-viewed ─────────────────────────────────────────────────────
// RequireAuth. Reads the projection then enriches via catalog (no cross-schema
// JOIN — the handler orchestrates the two reads, ordered by recency).

func handleRecentlyViewed(
	svc analytics.Service,
	catalogSvc catalog.Service,
	defaultLocale, defaultMarket, cashbackCurrency string,
) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		limit := atoiDefault(r.URL.Query().Get("limit"), 20)
		items, err := svc.RecentlyViewed(r.Context(), userID, limit)
		if err != nil {
			slog.Error("analytics: recently viewed", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if len(items) == 0 {
			jsonOK(w, http.StatusOK, map[string]any{"data": []any{}})
			return
		}
		ids := make([]int64, len(items))
		for i, it := range items {
			ids[i] = it.ProductID
		}
		locale := parseLocale(r, defaultLocale)
		rows, err := catalogSvc.ListProductsByIDs(r.Context(), ids, locale, defaultMarket)
		if err != nil {
			slog.Error("analytics: recently viewed enrich", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		// Preserve recency order (ListProductsByIDs does not guarantee it).
		byID := make(map[int64]catalog.ProductSummaryRow, len(rows))
		for _, row := range rows {
			byID[row.ID] = row
		}
		out := make([]productSummaryJSON, 0, len(items))
		for _, it := range items {
			if row, ok := byID[it.ProductID]; ok {
				out = append(out, buildProductSummaryJSON(row, cashbackCurrency))
			}
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": out})
	}
}
