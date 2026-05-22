package main

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/internal/identity/middleware"
)

// handleListAddresses GET /v1/addresses
func handleListAddresses(svc identity.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		addrs, err := svc.ListAddresses(r.Context(), userID)
		if err != nil {
			slog.Error("identity: ListAddresses", "user_id", userID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": addrs})
	}
}

// handleCreateAddress POST /v1/addresses
func handleCreateAddress(svc identity.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		var in identity.AddressInput
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		if in.Label == "" || in.Name == "" || in.FullAddress == "" || in.District == "" || in.City == "" {
			jsonError(w, "label, name, full_address, district, city required", http.StatusUnprocessableEntity)
			return
		}
		addr, err := svc.CreateAddress(r.Context(), userID, in)
		if err != nil {
			if errors.Is(err, identity.ErrAddressInvalidPhone) {
				jsonError(w, "address phone must be E.164 format", http.StatusUnprocessableEntity)
				return
			}
			slog.Error("identity: CreateAddress", "user_id", userID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusCreated, addr)
	}
}

// handleGetAddress GET /v1/addresses/{id}
func handleGetAddress(svc identity.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		addrID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid address id", http.StatusBadRequest)
			return
		}
		addr, err := svc.GetAddress(r.Context(), userID, addrID)
		if err != nil {
			if errors.Is(err, identity.ErrAddressNotFound) {
				jsonError(w, "address not found", http.StatusNotFound)
				return
			}
			slog.Error("identity: GetAddress", "user_id", userID, "address_id", addrID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, addr)
	}
}

// handleUpdateAddress PUT /v1/addresses/{id}
func handleUpdateAddress(svc identity.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		addrID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid address id", http.StatusBadRequest)
			return
		}
		var in identity.AddressInput
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		if in.Label == "" || in.Name == "" || in.FullAddress == "" || in.District == "" || in.City == "" {
			jsonError(w, "label, name, full_address, district, city required", http.StatusUnprocessableEntity)
			return
		}
		addr, err := svc.UpdateAddress(r.Context(), userID, addrID, in)
		if err != nil {
			switch {
			case errors.Is(err, identity.ErrAddressNotFound):
				jsonError(w, "address not found", http.StatusNotFound)
			case errors.Is(err, identity.ErrAddressInvalidPhone):
				jsonError(w, "address phone must be E.164 format", http.StatusUnprocessableEntity)
			default:
				slog.Error("identity: UpdateAddress", "user_id", userID, "address_id", addrID, "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		jsonOK(w, http.StatusOK, addr)
	}
}

// handleDeleteAddress DELETE /v1/addresses/{id}
func handleDeleteAddress(svc identity.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		addrID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid address id", http.StatusBadRequest)
			return
		}
		if err := svc.DeleteAddress(r.Context(), userID, addrID); err != nil {
			if errors.Is(err, identity.ErrAddressNotFound) {
				jsonError(w, "address not found", http.StatusNotFound)
				return
			}
			slog.Error("identity: DeleteAddress", "user_id", userID, "address_id", addrID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}
