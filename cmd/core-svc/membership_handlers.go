package main

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/order"
)

// handleGetMyMembership serves GET /me/membership (AC-05 phase 1): the
// authenticated user's derived membership tier. Pure read — the tier is
// computed per-request by order.MembershipService (delivered orders in the
// rolling window vs the ref_schema.membership_tiers ladder); nothing is stored
// and no money moves.
func handleGetMyMembership(svc order.MembershipService, defaultMarket string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		m, err := svc.GetMembershipTier(r.Context(), userID, defaultMarket)
		if err != nil {
			if errors.Is(err, order.ErrNoMembershipTiers) {
				// Provisioning error (the seed always includes the base tier).
				slog.Error("membership: no tiers for market", "market", defaultMarket)
			} else {
				slog.Error("membership: GetMembershipTier", "err", err, "user_id", userID)
			}
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, m)
	}
}
