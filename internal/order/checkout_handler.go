package order

import (
	"encoding/json"
	"errors"
	"net/http"
)

// checkoutInitiateRequest is the JSON body for POST /checkout/initiate.
type checkoutInitiateRequest struct {
	ReservationID string `json:"reservation_id"`
	Market        string `json:"market,omitempty"`
	Currency      string `json:"currency,omitempty"`
	CouponCode    string `json:"coupon_code,omitempty"`
	BuyerName     string `json:"buyer_name"`
	BuyerSurname  string `json:"buyer_surname"`
	BuyerEmail    string `json:"buyer_email"`
	ReturnURL     string `json:"return_url,omitempty"`
}

type checkoutInitiateResponse struct {
	SessionID   string  `json:"session_id"`
	ThreeDSHTML string  `json:"three_ds_html"`
	SipayURL    string  `json:"sipay_3ds_url,omitempty"` // web redirect URL
	Orders      []Order `json:"orders"`
}

// HandleInitiateCheckout returns an http.HandlerFunc for POST /checkout/initiate.
// userIDFromContext must be injected by the auth middleware (JWT claim).
func HandleInitiateCheckout(svc Service, userIDFromContext func(*http.Request) (int64, bool)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sessionID := r.Header.Get("Idempotency-Key")
		if sessionID == "" {
			http.Error(w, `{"error":"Idempotency-Key header required"}`, http.StatusUnprocessableEntity)
			return
		}

		userID, ok := userIDFromContext(r)
		if !ok {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}

		var body checkoutInitiateRequest
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
			return
		}

		resp, err := svc.InitiateCheckout(r.Context(), InitiateCheckoutRequest{
			UserID:        userID,
			ReservationID: body.ReservationID,
			Market:        body.Market,
			Currency:      body.Currency,
			CouponCode:    body.CouponCode,
			SessionID:     sessionID,
			BuyerName:     body.BuyerName,
			BuyerSurname:  body.BuyerSurname,
			BuyerEmail:    body.BuyerEmail,
			ReturnURL:     body.ReturnURL,
		})
		if err != nil {
			checkoutError(w, err)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(checkoutInitiateResponse{
			SessionID:   resp.SessionID,
			ThreeDSHTML: resp.ThreeDSHTML,
			SipayURL:    resp.ThreeDSURL,
			Orders:      resp.Orders,
		})
	}
}

func checkoutError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrDiskPanic):
		http.Error(w, `{"error":"service temporarily unavailable"}`, http.StatusServiceUnavailable)
	case errors.Is(err, ErrEmptyCart):
		http.Error(w, `{"error":"cart is empty"}`, http.StatusUnprocessableEntity)
	case errors.Is(err, ErrPSPNotConfigured):
		http.Error(w, `{"error":"payment provider not configured"}`, http.StatusInternalServerError)
	case errors.Is(err, ErrCheckoutSessionRequired):
		http.Error(w, `{"error":"Idempotency-Key header required"}`, http.StatusUnprocessableEntity)
	case errors.Is(err, ErrReservationExpired):
		http.Error(w, `{"error":"reservation expired, please re-reserve"}`, http.StatusConflict)
	default:
		http.Error(w, `{"error":"checkout failed"}`, http.StatusInternalServerError)
	}
}
