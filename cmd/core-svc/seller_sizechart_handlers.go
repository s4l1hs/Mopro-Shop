package main

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/seller"
)

// Seller-entered size charts (docs/internal/seller-size-charts.md). Role-gated
// writes; chart ownership is enforced in the seller repo (404, no existence
// leak), product ownership is checked here against catalog (§5 in-process read).

// handleCreateSizeChart: POST /seller/size-charts — create a validated chart.
func handleCreateSizeChart(sellerSvc seller.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		sellerID := middleware.SellerIDFromCtx(r.Context())
		var chart seller.SizeChart
		if err := decodeJSON(w, r, &chart); err != nil {
			return
		}
		id, err := sellerSvc.CreateSizeChart(r.Context(), sellerID, chart)
		switch {
		case err == nil:
			jsonOK(w, http.StatusCreated, map[string]any{"id": id})
		case errors.Is(err, seller.ErrInvalidChart):
			jsonError(w, "invalid size chart: "+err.Error(), http.StatusUnprocessableEntity)
		default:
			slog.Error("seller: CreateSizeChart", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}

// handleUpdateSizeChart: PUT /seller/size-charts/{id} — replace an owned chart.
func handleUpdateSizeChart(sellerSvc seller.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		sellerID := middleware.SellerIDFromCtx(r.Context())
		chartID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid chart id", http.StatusBadRequest)
			return
		}
		var chart seller.SizeChart
		if err := decodeJSON(w, r, &chart); err != nil {
			return
		}
		switch err := sellerSvc.UpdateSizeChart(r.Context(), sellerID, chartID, chart); {
		case err == nil:
			jsonOK(w, http.StatusOK, map[string]any{"id": chartID})
		case errors.Is(err, seller.ErrInvalidChart):
			jsonError(w, "invalid size chart: "+err.Error(), http.StatusUnprocessableEntity)
		case errors.Is(err, seller.ErrChartNotFound):
			jsonError(w, "size chart not found", http.StatusNotFound)
		default:
			slog.Error("seller: UpdateSizeChart", "chart_id", chartID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}

// handleListSizeCharts: GET /seller/size-charts — the seller's charts (+ rows).
func handleListSizeCharts(sellerSvc seller.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sellerID := middleware.SellerIDFromCtx(r.Context())
		charts, err := sellerSvc.ListSizeCharts(r.Context(), sellerID)
		if err != nil {
			slog.Error("seller: ListSizeCharts", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if charts == nil {
			charts = []seller.SizeChart{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"charts": charts})
	}
}

// sellerOwnsProduct confirms the authenticated seller owns the product (§5
// in-process catalog read). 404 on any mismatch — never leak another seller's
// product.
func sellerOwnsProduct(r *http.Request, catalogSvc catalog.Service, sellerID, productID int64) bool {
	product, _, _, err := catalogSvc.GetByID(r.Context(), productID)
	return err == nil && product.SellerID == sellerID
}

// handleAttachProductChart: POST /seller/products/{id}/size-chart — attach a chart.
func handleAttachProductChart(sellerSvc seller.Service, catalogSvc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		sellerID := middleware.SellerIDFromCtx(r.Context())
		productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		var body struct {
			ChartID int64 `json:"chart_id"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		if !sellerOwnsProduct(r, catalogSvc, sellerID, productID) {
			jsonError(w, "product not found", http.StatusNotFound)
			return
		}
		switch err := sellerSvc.AttachProductChart(r.Context(), sellerID, productID, body.ChartID); {
		case err == nil:
			jsonOK(w, http.StatusOK, map[string]any{"product_id": productID, "chart_id": body.ChartID})
		case errors.Is(err, seller.ErrChartNotFound):
			jsonError(w, "size chart not found", http.StatusNotFound)
		default:
			slog.Error("seller: AttachProductChart", "product_id", productID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}

// handleDetachProductChart: DELETE /seller/products/{id}/size-chart — falls back
// to the standard baseline.
func handleDetachProductChart(sellerSvc seller.Service, catalogSvc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		sellerID := middleware.SellerIDFromCtx(r.Context())
		productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		if !sellerOwnsProduct(r, catalogSvc, sellerID, productID) {
			jsonError(w, "product not found", http.StatusNotFound)
			return
		}
		switch err := sellerSvc.DetachProductChart(r.Context(), sellerID, productID); {
		case err == nil:
			w.WriteHeader(http.StatusNoContent)
		case errors.Is(err, seller.ErrChartNotFound):
			jsonError(w, "no chart attached", http.StatusNotFound)
		default:
			slog.Error("seller: DetachProductChart", "product_id", productID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}
