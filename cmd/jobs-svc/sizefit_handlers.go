package main

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strconv"

	"github.com/mopro/platform/internal/sizefinder"
)

// Size-fit internal endpoints (docs/internal/size-fit.md) — the serving half of
// the FIRST core→jobs §3.4 synchronous HTTP path. These are NOT consumer
// routes: Caddy publicly routes only /jobs/* to jobs-svc, so /internal/* is
// unreachable from outside; core-svc reaches them over mopro-net. Defense in
// depth: every request must carry X-Internal-Token == ADMIN_INTERNAL_TOKEN
// (already provisioned in the shared env_file).

// registerSizefitRoutes wires the internal size-fit API onto the jobs-svc mux.
func registerSizefitRoutes(mux *http.ServeMux, svc sizefinder.Service) {
	token := os.Getenv("ADMIN_INTERNAL_TOKEN")
	guard := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if token == "" || r.Header.Get("X-Internal-Token") != token {
				http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
				return
			}
			next(w, r)
		}
	}

	mux.HandleFunc("PUT /internal/sizefit/profile", guard(func(w http.ResponseWriter, r *http.Request) {
		var p sizefinder.FitProfile
		if err := json.NewDecoder(r.Body).Decode(&p); err != nil || p.UserID == 0 {
			http.Error(w, `{"error":"bad_request"}`, http.StatusBadRequest)
			return
		}
		if err := svc.UpsertProfile(r.Context(), p); err != nil {
			if errors.Is(err, sizefinder.ErrInvalidMeasurement) {
				http.Error(w, `{"error":"invalid_measurement"}`, http.StatusUnprocessableEntity)
				return
			}
			slog.Error("sizefit: upsert profile", "err", err)
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))

	mux.HandleFunc("GET /internal/sizefit/profile", guard(func(w http.ResponseWriter, r *http.Request) {
		userID, err := parseUserID(r.URL.Query().Get("user_id"))
		if err != nil {
			http.Error(w, `{"error":"bad_request"}`, http.StatusBadRequest)
			return
		}
		p, err := svc.GetProfile(r.Context(), userID)
		if errors.Is(err, sizefinder.ErrProfileNotFound) {
			http.Error(w, `{"error":"not_found"}`, http.StatusNotFound)
			return
		}
		if err != nil {
			slog.Error("sizefit: get profile", "err", err)
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(p)
	}))

	mux.HandleFunc("POST /internal/sizefit/recommend", guard(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			UserID int64  `json:"user_id"`
			Title  string `json:"title"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.UserID == 0 {
			http.Error(w, `{"error":"bad_request"}`, http.StatusBadRequest)
			return
		}
		rec, err := svc.Recommend(r.Context(), req.UserID, req.Title)
		if err != nil {
			slog.Error("sizefit: recommend", "err", err)
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(rec)
	}))
}

// parseUserID parses a positive int64 user id.
func parseUserID(s string) (int64, error) {
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil || v <= 0 {
		return 0, errors.New("invalid user_id")
	}
	return v, nil
}
