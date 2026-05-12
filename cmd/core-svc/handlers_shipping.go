package main

import (
	"errors"
	"io"
	"log/slog"
	"net/http"

	"github.com/mopro/platform/internal/shipping"
)

// handleShippingWebhook is a generic carrier webhook handler that:
//  1. Reads the raw body (needed for HMAC verification)
//  2. Delegates signature verification + parsing to the carrier adapter via svc.HandleWebhook
//  3. Processes the normalised event via svc.ProcessWebhookEvent
//
// Returns 200 OK even for unknown tracking numbers so the carrier does not retry.
// Returns 400 only for invalid signatures (carrier should NOT retry on auth failure).
func handleShippingWebhook(svc shipping.Service, carrier string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rawBody, err := io.ReadAll(r.Body)
		if err != nil {
			slog.Warn("shipping webhook: read body", "carrier", carrier, "err", err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		headers := make(map[string]string, 8)
		for k := range r.Header {
			headers[k] = r.Header.Get(k)
		}

		event, err := svc.HandleWebhook(r.Context(), carrier, rawBody, headers)
		if err != nil {
			if errors.Is(err, shipping.ErrInvalidSignature) {
				slog.Warn("shipping webhook: invalid signature", "carrier", carrier)
				jsonError(w, "invalid signature", http.StatusBadRequest)
				return
			}
			slog.Error("shipping webhook: HandleWebhook", "carrier", carrier, "err", err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		if err := svc.ProcessWebhookEvent(r.Context(), carrier, event); err != nil {
			slog.Error("shipping webhook: ProcessWebhookEvent", "carrier", carrier, "err", err)
			// Return 500 so the carrier retries (unknown tracking already returns nil inside ProcessWebhookEvent).
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
	}
}
