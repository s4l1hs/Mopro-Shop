package main

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/inbox"
)

func handleListNotifications(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		unreadOnly := r.URL.Query().Get("filter") == "unread"
		page := atoiDefault(r.URL.Query().Get("page"), 1)
		pageSize := atoiDefault(r.URL.Query().Get("pageSize"), 20)

		items, total, err := svc.List(r.Context(), userID, unreadOnly, page, pageSize)
		if err != nil {
			slog.Error("inbox: List", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if items == nil {
			items = []inbox.Notification{}
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"data":     items,
			"total":    total,
			"page":     page,
			"pageSize": pageSize,
			"hasMore":  page*pageSize < total,
		})
	}
}

func handleUnreadCount(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		n, err := svc.UnreadCount(r.Context(), userID)
		if err != nil {
			slog.Error("inbox: UnreadCount", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"count": n})
	}
}

func handleMarkNotificationRead(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid notification id", http.StatusBadRequest)
			return
		}
		if err := svc.MarkRead(r.Context(), userID, id); err != nil {
			slog.Error("inbox: MarkRead", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleMarkAllRead(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		marked, err := svc.MarkAllRead(r.Context(), userID)
		if err != nil {
			slog.Error("inbox: MarkAllRead", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"marked": marked})
	}
}

func handleGetPreferences(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		prefs, err := svc.GetPreferences(r.Context(), userID)
		if err != nil {
			slog.Error("inbox: GetPreferences", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"preferences": prefs})
	}
}

func handlePutPreferences(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			Preferences []inbox.Preference `json:"preferences"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		if err := svc.UpsertPreferences(r.Context(), userID, body.Preferences); err != nil {
			if errors.Is(err, inbox.ErrInvalidPreference) {
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}
			slog.Error("inbox: UpsertPreferences", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleRegisterPushToken(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			Token    string `json:"token"`
			Platform string `json:"platform"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		if err := svc.RegisterPushToken(r.Context(), userID, body.Token, body.Platform); err != nil {
			if errors.Is(err, inbox.ErrInvalidPlatform) || errors.Is(err, inbox.ErrInvalidPushToken) {
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}
			slog.Error("inbox: RegisterPushToken", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleDeletePushToken(svc inbox.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			Token string `json:"token"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		if err := svc.DeletePushToken(r.Context(), userID, body.Token); err != nil {
			if errors.Is(err, inbox.ErrInvalidPushToken) {
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}
			slog.Error("inbox: DeletePushToken", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}
