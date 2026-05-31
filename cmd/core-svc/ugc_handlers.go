package main

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/seller"
)

// ── Reviews write-side ────────────────────────────────────────────────────────

func handleCreateReview(svc catalog.ReviewWriteService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, err := strconv.ParseInt(r.PathValue("productId"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			Rating          int    `json:"rating"`
			Title           string `json:"title"`
			Body            string `json:"body"`
			SubmittedLocale string `json:"submittedLocale"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		rec, err := svc.CreateReview(r.Context(), catalog.ReviewInput{
			ProductID: productID, UserID: userID, Rating: body.Rating,
			Title: body.Title, Body: body.Body, SubmittedLocale: localeOrDefault(body.SubmittedLocale),
		})
		if err != nil {
			if errors.Is(err, catalog.ErrReviewExists) {
				existing, _ := svc.UserReviewID(r.Context(), userID, productID)
				jsonOK(w, http.StatusConflict, map[string]any{
					"error":            "review already exists",
					"existingReviewId": existing,
				})
				return
			}
			if isReviewValidationErr(err) {
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}
			slog.Error("catalog: CreateReview", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusCreated, map[string]any{"review": rec})
	}
}

func handleUpdateReview(svc catalog.ReviewWriteService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, _ := strconv.ParseInt(r.PathValue("productId"), 10, 64)
		reviewID, err := strconv.ParseInt(r.PathValue("reviewId"), 10, 64)
		if err != nil {
			jsonError(w, "invalid review id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			Rating          int    `json:"rating"`
			Title           string `json:"title"`
			Body            string `json:"body"`
			SubmittedLocale string `json:"submittedLocale"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		rec, err := svc.UpdateReview(r.Context(), userID, reviewID, catalog.ReviewInput{
			ProductID: productID, UserID: userID, Rating: body.Rating,
			Title: body.Title, Body: body.Body, SubmittedLocale: localeOrDefault(body.SubmittedLocale),
		})
		if err != nil {
			switch {
			case errors.Is(err, catalog.ErrReviewNotFound):
				jsonError(w, "review not found", http.StatusNotFound)
			case isReviewValidationErr(err):
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
			default:
				slog.Error("catalog: UpdateReview", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"review": rec})
	}
}

func handleDeleteReview(svc catalog.ReviewWriteService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		reviewID, err := strconv.ParseInt(r.PathValue("reviewId"), 10, 64)
		if err != nil {
			jsonError(w, "invalid review id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		if err := svc.DeleteReview(r.Context(), userID, reviewID); err != nil {
			if errors.Is(err, catalog.ErrReviewNotFound) {
				jsonError(w, "review not found", http.StatusNotFound)
				return
			}
			slog.Error("catalog: DeleteReview", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleListUserReviews(svc catalog.ReviewWriteService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		page := atoiDefault(r.URL.Query().Get("page"), 1)
		pageSize := atoiDefault(r.URL.Query().Get("pageSize"), 20)
		items, total, err := svc.ListUserReviews(r.Context(), userID, pageSize, (page-1)*pageSize)
		if err != nil {
			slog.Error("catalog: ListUserReviews", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if items == nil {
			items = []catalog.UserReview{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": items, "total": total, "page": page, "hasMore": page*pageSize < total})
	}
}

// handleReviewEligibility orchestrates order (delivered + window) + catalog
// (variant→product + existing review) to compute the review block server-side.
func handleReviewEligibility(reviewSvc catalog.ReviewWriteService, catalogSvc catalog.Service, orderSvc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		existing, _ := reviewSvc.UserReviewID(r.Context(), userID, productID)

		elig := catalog.ReviewEligibility{ExistingReviewID: existing}
		// Product's variant id set.
		_, variants, _, err := catalogSvc.GetByID(r.Context(), productID)
		if err != nil {
			jsonOK(w, http.StatusOK, map[string]any{"eligibility": elig})
			return
		}
		variantSet := map[int64]bool{}
		for _, v := range variants {
			variantSet[v.ID] = true
		}
		// Scan the user's delivered orders within the window for a matching item.
		orders, _ := orderSvc.ListOrders(r.Context(), userID)
		cutoff := time.Now().UTC().AddDate(0, 0, -catalog.ReviewWindowDays)
		var latest *time.Time
		for _, o := range orders {
			if o.Status != order.StatusDelivered || o.DeliveredAt == nil || o.DeliveredAt.Before(cutoff) {
				continue
			}
			_, items, e := orderSvc.GetOrder(r.Context(), o.ID)
			if e != nil {
				continue
			}
			for _, it := range items {
				if variantSet[it.VariantID] {
					d := *o.DeliveredAt
					if latest == nil || d.After(*latest) {
						latest = &d
					}
				}
			}
		}
		if latest != nil {
			until := latest.AddDate(0, 0, catalog.ReviewWindowDays)
			elig.ReviewableUntil = &until
			elig.CanReview = existing == 0
		}
		jsonOK(w, http.StatusOK, map[string]any{"eligibility": elig})
	}
}

// ── Q&A ───────────────────────────────────────────────────────────────────────

func handleCreateQuestion(svc catalog.QAService, idSvc identity.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, err := strconv.ParseInt(r.PathValue("productId"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			Body            string `json:"body"`
			SubmittedLocale string `json:"submittedLocale"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		q, err := svc.CreateQuestion(r.Context(), catalog.QuestionInput{
			ProductID: productID, UserID: userID, AuthorName: displayName(r, idSvc, userID),
			Body: body.Body, SubmittedLocale: localeOrDefault(body.SubmittedLocale),
		})
		if err != nil {
			if isReviewValidationErr(err) {
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}
			slog.Error("catalog: CreateQuestion", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusCreated, map[string]any{"question": q})
	}
}

func handleListQuestions(svc catalog.QAService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, err := strconv.ParseInt(r.PathValue("productId"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		page := atoiDefault(r.URL.Query().Get("page"), 1)
		pageSize := atoiDefault(r.URL.Query().Get("pageSize"), 10)
		sort := catalog.ParseQuestionSort(r.URL.Query().Get("sort"))
		items, total, err := svc.ListQuestions(r.Context(), productID, sort, pageSize, (page-1)*pageSize)
		if err != nil {
			slog.Error("catalog: ListQuestions", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if items == nil {
			items = []catalog.Question{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": items, "total": total, "page": page, "hasMore": page*pageSize < total})
	}
}

func handleGetQuestion(svc catalog.QAService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		questionID, err := strconv.ParseInt(r.PathValue("questionId"), 10, 64)
		if err != nil {
			jsonError(w, "invalid question id", http.StatusBadRequest)
			return
		}
		q, answers, err := svc.GetQuestion(r.Context(), questionID)
		if err != nil {
			if errors.Is(err, catalog.ErrQuestionNotFound) {
				jsonError(w, "question not found", http.StatusNotFound)
				return
			}
			slog.Error("catalog: GetQuestion", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if answers == nil {
			answers = []catalog.Answer{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"question": q, "answers": answers})
	}
}

func handleCreateAnswer(svc catalog.QAService, idSvc identity.Service, sellerSvc seller.Service, reader catalog.SellerStorefrontReader) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		questionID, err := strconv.ParseInt(r.PathValue("questionId"), 10, 64)
		if err != nil {
			jsonError(w, "invalid question id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			Body            string `json:"body"`
			SubmittedLocale string `json:"submittedLocale"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		a, err := svc.CreateAnswer(r.Context(), catalog.AnswerInput{
			QuestionID: questionID, UserID: userID, AuthorName: displayName(r, idSvc, userID),
			Body: body.Body, SubmittedLocale: localeOrDefault(body.SubmittedLocale),
			IsSeller: answerIsFromSeller(r, svc, sellerSvc, reader, userID, questionID),
		})
		if err != nil {
			if isReviewValidationErr(err) {
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
				return
			}
			slog.Error("catalog: CreateAnswer", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusCreated, map[string]any{"answer": a})
	}
}

func handleListUserQuestions(svc catalog.QAService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		page := atoiDefault(r.URL.Query().Get("page"), 1)
		pageSize := atoiDefault(r.URL.Query().Get("pageSize"), 20)
		items, total, err := svc.ListUserQuestions(r.Context(), userID, pageSize, (page-1)*pageSize)
		if err != nil {
			slog.Error("catalog: ListUserQuestions", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if items == nil {
			items = []catalog.Question{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": items, "total": total, "page": page, "hasMore": page*pageSize < total})
	}
}

// answerIsFromSeller reports whether the answering user is the seller who owns
// the product the question is about (drives the "Satıcı" badge on the answer).
func answerIsFromSeller(r *http.Request, qaSvc catalog.QAService, sellerSvc seller.Service, reader catalog.SellerStorefrontReader, userID, questionID int64) bool {
	sellerID, isSeller, err := sellerSvc.ResolveSellerForUser(r.Context(), userID)
	if err != nil || !isSeller {
		return false
	}
	q, _, err := qaSvc.GetQuestion(r.Context(), questionID)
	if err != nil {
		return false
	}
	productSellerID, err := reader.ProductSellerID(r.Context(), q.ProductID)
	if err != nil {
		return false
	}
	return productSellerID == sellerID
}

func isReviewValidationErr(err error) bool {
	return errors.Is(err, catalog.ErrInvalidRating) ||
		errors.Is(err, catalog.ErrEmptyBody) ||
		errors.Is(err, catalog.ErrBodyTooLong) ||
		errors.Is(err, catalog.ErrTitleTooLong)
}

func localeOrDefault(l string) string {
	if l == "" {
		return "tr"
	}
	return l
}

// displayName resolves the user's display name for denormalized authorship.
func displayName(r *http.Request, idSvc identity.Service, userID int64) string {
	u, err := idSvc.GetMe(r.Context(), userID)
	if err != nil || u.Name == "" {
		return "Kullanıcı"
	}
	return u.Name
}
