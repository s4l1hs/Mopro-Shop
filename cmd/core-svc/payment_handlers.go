package main

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/internal/payment/sipay"
)

// handleInitiatePayment handles POST /payments — starts a 3DS session.
// Requires Idempotency-Key header and Bearer JWT auth (via RequireAuth middleware).
func handleInitiatePayment(svc payment.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		_ = middleware.UserIDFromCtx(r.Context())
		var body payment.InitiatePaymentRequest
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		body.IdempotencyKey = r.Header.Get("Idempotency-Key")

		resp, err := svc.InitiatePayment(r.Context(), body)
		if err != nil {
			switch {
			case errors.Is(err, payment.ErrInvalidAmount):
				jsonError(w, "amount must be positive", http.StatusUnprocessableEntity)
			case errors.Is(err, payment.ErrPaymentAlreadyCaptured):
				jsonError(w, "payment already captured", http.StatusConflict)
			case errors.Is(err, payment.ErrProviderNotImplemented):
				jsonError(w, "payment provider not available", http.StatusServiceUnavailable)
			default:
				slog.Error("payment: InitiatePayment", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		jsonOK(w, http.StatusCreated, resp)
	}
}

// handlePaymentStatus handles GET /payments/{provider_ref}/status — polls PSP.
func handlePaymentStatus(svc payment.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ref := r.PathValue("provider_ref")
		if ref == "" {
			jsonError(w, "provider_ref required", http.StatusBadRequest)
			return
		}
		status, err := svc.CheckStatus(r.Context(), ref)
		if err != nil {
			if errors.Is(err, payment.ErrProviderNotImplemented) {
				jsonError(w, "payment provider not available", http.StatusServiceUnavailable)
				return
			}
			slog.Error("payment: CheckStatus", "err", err, "provider_ref", ref)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]string{"status": string(status)})
	}
}

// handlePaymentIntentStatus handles GET /payments/{invoiceID}/intent-status.
// Returns the DB-stored payment status without calling the PSP. Used by the web
// polling loop on /checkout/redirect to detect when the Sipay webhook has landed.
// No auth required — invoiceID is a cryptographically random UUID (unguessable).
func handlePaymentIntentStatus(repo payment.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		invoiceID := r.PathValue("invoiceID")
		if invoiceID == "" {
			jsonError(w, "invoiceID required", http.StatusBadRequest)
			return
		}
		intent, err := repo.FindPaymentIntentByIdempotencyKey(r.Context(), invoiceID)
		if errors.Is(err, payment.ErrPaymentNotFound) {
			// Webhook hasn't arrived yet; webhook is source of truth.
			jsonOK(w, http.StatusOK, map[string]any{"status": "pending"})
			return
		}
		if err != nil {
			slog.Error("payment: FindPaymentIntentByIdempotencyKey", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		resp := map[string]any{"status": string(intent.Status), "order_id": intent.OrderID}
		if intent.FailureReason != "" {
			resp["failure_reason"] = intent.FailureReason
		}
		jsonOK(w, http.StatusOK, resp)
	}
}

// handleSipayWebhook wraps the Sipay WebhookHandler as an http.HandlerFunc.
// The actual handler is a *sipay.WebhookHandler injected at startup.
func handleSipayWebhook(h *sipay.WebhookHandler) http.HandlerFunc {
	return h.ServeHTTP
}
