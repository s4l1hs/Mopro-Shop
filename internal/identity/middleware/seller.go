package middleware

import (
	"context"
	"log/slog"
	"net/http"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/mopro/platform/pkg/logx"
)

const ctxKeySellerID contextKey = "identity.seller_id"

// SellerLookup resolves the seller a user owns/staffs. It returns
// (sellerID, true, nil) when the user is bound to a seller, (0, false, nil)
// when they are not, and a non-nil error only on infrastructure failure.
//
// A func type (rather than importing internal/seller) keeps the identity
// package free of a seller dependency; cmd/core-svc wires the concrete
// seller.Service.ResolveSellerForUser into it.
type SellerLookup func(ctx context.Context, userID int64) (sellerID int64, isSeller bool, err error)

// RequireSellerRole gates a route to authenticated users who are bound to a
// seller. It MUST be applied AFTER RequireAuth so the user ID is in context.
// On success it stores the resolved seller ID in the context (read via
// SellerIDFromCtx) and calls next; otherwise it responds 403.
func RequireSellerRole(lookup SellerLookup) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			userID := UserIDFromCtx(r.Context())
			if userID == 0 {
				http.Error(w, `{"error":"missing_token"}`, http.StatusUnauthorized)
				return
			}
			sellerID, isSeller, err := lookup(r.Context(), userID)
			if err != nil {
				http.Error(w, `{"error":"seller_lookup_failed"}`, http.StatusInternalServerError)
				return
			}
			if !isSeller {
				http.Error(w, `{"error":"not_a_seller"}`, http.StatusForbidden)
				return
			}
			ctx := context.WithValue(r.Context(), ctxKeySellerID, sellerID)
			span := trace.SpanFromContext(ctx)
			span.SetAttributes(attribute.Int64("seller_id", sellerID))
			ctx = logx.With(ctx, slog.Int64("seller_id", sellerID))
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// ContextWithSellerID returns a copy of ctx carrying the given seller ID under
// the key RequireSellerRole uses. Useful for tests and internal callers.
func ContextWithSellerID(ctx context.Context, sellerID int64) context.Context {
	return context.WithValue(ctx, ctxKeySellerID, sellerID)
}

// SellerIDFromCtx returns the resolved seller ID from the context, or 0 if the
// RequireSellerRole middleware was not applied.
func SellerIDFromCtx(ctx context.Context) int64 {
	if v, ok := ctx.Value(ctxKeySellerID).(int64); ok {
		return v
	}
	return 0
}
