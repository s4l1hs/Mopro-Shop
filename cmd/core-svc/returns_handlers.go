package main

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/pkg/mediaurl"
)

// cdnURLsFromKeys maps storage keys to CDN urls (RT-03 evidence photos); nil/empty
// → nil so returnJSON omits the key.
func cdnURLsFromKeys(keys []string) []string {
	if len(keys) == 0 {
		return nil
	}
	urls := make([]string, 0, len(keys))
	for _, k := range keys {
		urls = append(urls, mediaurl.CDNUrl(k))
	}
	return urls
}

// refundEstimateDays is how long after initiation a pending refund is estimated
// to settle to the buyer (display-only).
const refundEstimateDays = 10

// refundView is the read-only refund block surfaced on order + return detail.
// Derived from the existing payment/return record — no new ledger writes.
type refundView struct {
	AmountMinor int64      `json:"amountMinor"`
	Currency    string     `json:"currency"`
	Method      string     `json:"method"` // original_payment | wallet_credit
	Status      string     `json:"status"` // pending | processing | issued | failed
	IssuedAt    *time.Time `json:"issuedAt"`
	EstimatedAt *time.Time `json:"estimatedAt"`
}

// buildOrderRefundView returns a refund block when the order is in a
// refund-relevant state, else nil. `found` indicates a payment record exists.
func buildOrderRefundView(o order.Order, pi payment.PaymentIntent, found bool) *refundView {
	relevant := o.Status == order.StatusCancelled ||
		o.Status == order.StatusRefunded ||
		o.Status == order.StatusPartiallyRefunded ||
		(found && pi.Status == payment.PaymentStatusRefunded)
	if !relevant {
		return nil
	}
	rv := &refundView{
		AmountMinor: o.TotalMinor,
		Currency:    o.Currency,
		Method:      "original_payment",
	}
	if found && pi.Status == payment.PaymentStatusRefunded {
		rv.Status = "issued"
		rv.IssuedAt = pi.RefundedAt
		if pi.RefundAmountMinor > 0 {
			rv.AmountMinor = pi.RefundAmountMinor
		}
	} else {
		rv.Status = "pending"
		est := o.UpdatedAt.AddDate(0, 0, refundEstimateDays)
		rv.EstimatedAt = &est
	}
	return rv
}

// buildReturnRefundView surfaces the refund block for a return request from its
// own snapshotted refund fields + lifecycle status. Method is wallet_credit: an
// approved return settles as Mopro Coin to the buyer's wallet (RT-01, the audit's
// refund-as-coin model) — not a PSP fiat reversal.
func buildReturnRefundView(r order.Return) *refundView {
	rv := &refundView{
		AmountMinor: r.RefundAmountMinor,
		Currency:    r.RefundCurrency,
		Method:      "wallet_credit",
	}
	switch r.Status {
	case order.ReturnRefunded:
		rv.Status = "issued"
		issued := r.UpdatedAt
		rv.IssuedAt = &issued
	case order.ReturnRejected:
		rv.Status = "failed"
	default: // pending | approved
		rv.Status = "pending"
		est := r.CreatedAt.AddDate(0, 0, refundEstimateDays)
		rv.EstimatedAt = &est
	}
	return rv
}

// returnJSON is the wire shape for a return (snake_case order fields, with the
// nested items + camelCase refund block used elsewhere on the orders surface).
// history is the append-only status timeline (RT-04); nil omits the key.
func returnJSON(r order.Return, items []order.ReturnItem, refund *refundView, history []order.ReturnStatusEvent, photoURLs []string) map[string]any {
	if items == nil {
		items = []order.ReturnItem{}
	}
	out := map[string]any{
		"id":          r.ID,
		"order_id":    r.OrderID,
		"status":      r.Status,
		"reason":      r.Reason,
		"description": r.Description,
		"created_at":  r.CreatedAt,
		"items":       items,
		"refund":      refund,
	}
	if history != nil {
		out["history"] = history
	}
	if photoURLs != nil {
		out["photo_urls"] = photoURLs // RT-03: evidence photos (CDN urls)
	}
	return out
}

// handleCreateReturn wires the OpenAPI CreateReturn op: POST /orders/{id}/returns.
func handleCreateReturn(returnSvc order.ReturnService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		orderID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid order id", http.StatusBadRequest)
			return
		}
		var body struct {
			Reason      string `json:"reason"`
			Description string `json:"description"`
			Items       []struct {
				OrderItemID int64  `json:"order_item_id"`
				Quantity    int    `json:"quantity"`
				Reason      string `json:"reason"` // RT-05: optional per-line reason
				Note        string `json:"note"`   // RT-05: optional per-line note
			} `json:"items"`
			PhotoKeys []string `json:"photo_keys"` // RT-03: evidence photo keys
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		in := order.ReturnInput{
			OrderID:     orderID,
			UserID:      middleware.UserIDFromCtx(r.Context()),
			Reason:      order.ReturnReason(body.Reason),
			Description: body.Description,
		}
		for _, it := range body.Items {
			in.Items = append(in.Items, order.ReturnItemInput{
				OrderItemID: it.OrderItemID,
				Quantity:    it.Quantity,
				Reason:      order.ReturnReason(it.Reason),
				Note:        it.Note,
			})
		}
		in.PhotoKeys = body.PhotoKeys

		rec, items, err := returnSvc.CreateReturn(r.Context(), in)
		if err != nil {
			switch {
			case errors.Is(err, order.ErrOrderNotFound):
				jsonError(w, "order not found", http.StatusNotFound)
			case errors.Is(err, order.ErrReturnWindowExpired):
				jsonError(w, "return window expired", http.StatusConflict)
			case errors.Is(err, order.ErrOrderNotDelivered),
				errors.Is(err, order.ErrItemNotInOrder),
				errors.Is(err, order.ErrQuantityExceedsReturn),
				errors.Is(err, order.ErrReturnAlreadyExists),
				errors.Is(err, order.ErrNoReturnableItems),
				errors.Is(err, order.ErrInvalidReturnReason):
				jsonError(w, err.Error(), http.StatusUnprocessableEntity)
			default:
				slog.Error("returns: CreateReturn", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		jsonOK(w, http.StatusCreated, returnJSON(rec, items, buildReturnRefundView(rec), nil, cdnURLsFromKeys(in.PhotoKeys)))
	}
}

// handleListReturns: GET /returns — the authenticated user's returns, newest first.
func handleListReturns(returnSvc order.ReturnService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		limit := atoiDefault(r.URL.Query().Get("limit"), 20)
		offset := atoiDefault(r.URL.Query().Get("offset"), 0)

		recs, err := returnSvc.ListReturns(r.Context(), userID, limit+1, offset)
		if err != nil {
			slog.Error("returns: ListReturns", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		hasMore := len(recs) > limit
		if hasMore {
			recs = recs[:limit]
		}
		data := make([]map[string]any, 0, len(recs))
		for _, rec := range recs {
			data = append(data, map[string]any{
				"id":                  rec.ID,
				"order_id":            rec.OrderID,
				"status":              rec.Status,
				"reason":              rec.Reason,
				"refund_amount_minor": rec.RefundAmountMinor,
				"refund_currency":     rec.RefundCurrency,
				"created_at":          rec.CreatedAt,
			})
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": data, "hasMore": hasMore})
	}
}

// handleGetReturn: GET /returns/{id} — ownership-scoped detail with refund block.
func handleGetReturn(returnSvc order.ReturnService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		returnID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid return id", http.StatusBadRequest)
			return
		}
		rec, items, err := returnSvc.GetReturn(r.Context(), userID, returnID)
		if err != nil {
			if errors.Is(err, order.ErrReturnNotFound) {
				jsonError(w, "return not found", http.StatusNotFound)
				return
			}
			slog.Error("returns: GetReturn", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		// RT-04: surface the append-only status timeline. Best-effort — a history
		// read failure degrades to the derived timeline rather than failing the page.
		history, hErr := returnSvc.GetReturnHistory(r.Context(), userID, returnID)
		if hErr != nil {
			slog.Warn("returns: GetReturnHistory", "err", hErr)
			history = []order.ReturnStatusEvent{}
		}
		// RT-03: evidence photos (best-effort — a read failure degrades to none).
		photoKeys, pErr := returnSvc.GetReturnPhotos(r.Context(), userID, returnID)
		if pErr != nil {
			slog.Warn("returns: GetReturnPhotos", "err", pErr)
		}
		photoURLs := cdnURLsFromKeys(photoKeys)
		if photoURLs == nil {
			photoURLs = []string{} // detail always carries the key (possibly empty)
		}
		jsonOK(w, http.StatusOK, returnJSON(rec, items, buildReturnRefundView(rec), history, photoURLs))
	}
}

func atoiDefault(s string, def int) int {
	if s == "" {
		return def
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return n
}
