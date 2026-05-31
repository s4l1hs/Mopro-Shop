package main

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/mopro/platform/internal/help"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/support"
)

// ── Help (public — no auth) ───────────────────────────────────────────────────

func handleHelpCategories(svc help.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cats, err := svc.ListCategories(r.Context(), parseLocale(r, defaultLocale))
		if err != nil {
			slog.Error("help: ListCategories", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"categories": cats})
	}
}

func handleHelpArticles(svc help.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		arts, err := svc.ListArticles(r.Context(), r.PathValue("slug"), parseLocale(r, defaultLocale))
		if err != nil {
			slog.Error("help: ListArticles", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"articles": arts})
	}
}

func handleHelpArticle(svc help.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		a, err := svc.GetArticle(r.Context(), r.PathValue("slug"), parseLocale(r, defaultLocale))
		if err != nil {
			if errors.Is(err, help.ErrArticleNotFound) {
				jsonError(w, "article not found", http.StatusNotFound)
				return
			}
			slog.Error("help: GetArticle", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"article": a})
	}
}

func handleHelpSearch(svc help.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		results, err := svc.Search(r.Context(), r.URL.Query().Get("q"), parseLocale(r, defaultLocale))
		if err != nil {
			slog.Error("help: Search", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if results == nil {
			results = []help.SearchResult{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"results": results})
	}
}

// ── Support tickets ───────────────────────────────────────────────────────────

// handleCreateTicket is OptionalAuth: guests submit with email only; authed
// users get user_id from the session.
func handleCreateTicket(svc support.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Email              string `json:"email"`
			Subject            string `json:"subject"`
			Body               string `json:"body"`
			Category           string `json:"category"`
			RelatedOrderID     int64  `json:"related_order_id"`
			RelatedArticleSlug string `json:"related_article_slug"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		t, err := svc.CreateTicket(r.Context(), support.TicketInput{
			UserID:             middleware.UserIDFromCtx(r.Context()),
			Email:              body.Email,
			Subject:            body.Subject,
			Body:               body.Body,
			Category:           body.Category,
			RelatedOrderID:     body.RelatedOrderID,
			RelatedArticleSlug: body.RelatedArticleSlug,
		})
		if err != nil {
			if isSupportValidationErr(err) {
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}
			slog.Error("support: CreateTicket", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusCreated, map[string]any{"ticket": t})
	}
}

func handleListTickets(svc support.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		page := atoiDefault(r.URL.Query().Get("page"), 1)
		pageSize := atoiDefault(r.URL.Query().Get("pageSize"), 20)
		tickets, err := svc.ListTickets(r.Context(), userID, page, pageSize)
		if err != nil {
			slog.Error("support: ListTickets", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if tickets == nil {
			tickets = []support.Ticket{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"tickets": tickets})
	}
}

func handleGetTicket(svc support.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid ticket id", http.StatusBadRequest)
			return
		}
		t, err := svc.GetTicket(r.Context(), userID, id)
		if err != nil {
			if errors.Is(err, support.ErrTicketNotFound) {
				jsonError(w, "ticket not found", http.StatusNotFound)
				return
			}
			slog.Error("support: GetTicket", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"ticket": t})
	}
}

func isSupportValidationErr(err error) bool {
	return errors.Is(err, support.ErrInvalidEmail) ||
		errors.Is(err, support.ErrEmptySubject) ||
		errors.Is(err, support.ErrSubjectTooLong) ||
		errors.Is(err, support.ErrEmptyBody) ||
		errors.Is(err, support.ErrBodyTooLong) ||
		errors.Is(err, support.ErrInvalidCategory)
}
