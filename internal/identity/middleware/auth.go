// Package middleware provides HTTP middleware for JWT authentication.
package middleware

import (
	"context"
	"log/slog"
	"net/http"
	"strings"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/mopro/platform/internal/identity/jwt"
	"github.com/mopro/platform/pkg/logx"
)

type contextKey string

const (
	ctxKeyUserID contextKey = "identity.user_id"
	ctxKeyClaims contextKey = "identity.claims"
)

// RequireAuth validates the Bearer JWT in Authorization header.
// On success, it stores the user ID and claims in the request context and calls next.
// On failure, it responds 401.
func RequireAuth(signer jwt.Signer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tok := bearerToken(r)
			if tok == "" {
				http.Error(w, `{"error":"missing_token"}`, http.StatusUnauthorized)
				return
			}
			claims, err := signer.Verify(tok)
			if err != nil {
				http.Error(w, `{"error":"invalid_token"}`, http.StatusUnauthorized)
				return
			}
			if claims.Scope != jwt.ScopeAPI {
				http.Error(w, `{"error":"wrong_scope"}`, http.StatusUnauthorized)
				return
			}
			ctx := context.WithValue(r.Context(), ctxKeyUserID, claims.UserID)
			ctx = context.WithValue(ctx, ctxKeyClaims, claims)
			// Attach user_id to the active OTel span and inject it into the ctx logger.
			span := trace.SpanFromContext(ctx)
			span.SetAttributes(attribute.Int64("user_id", claims.UserID))
			ctx = logx.With(ctx, slog.Int64("user_id", claims.UserID))
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireStepUp validates that the request carries a valid step-up JWT (scope="high_sensitivity").
// Must be applied AFTER RequireAuth so the base user ID is already in context.
func RequireStepUp(signer jwt.Signer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tok := r.Header.Get("X-Mopro-Step-Up-Token")
			if tok == "" {
				http.Error(w, `{"error":"step_up_required"}`, http.StatusForbidden)
				return
			}
			claims, err := signer.Verify(tok)
			if err != nil || claims.Scope != jwt.ScopeStepUp {
				http.Error(w, `{"error":"step_up_invalid"}`, http.StatusForbidden)
				return
			}
			// Verify step-up belongs to the same user as the access token.
			baseUserID := UserIDFromCtx(r.Context())
			if baseUserID == 0 || claims.UserID != baseUserID {
				http.Error(w, `{"error":"step_up_user_mismatch"}`, http.StatusForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// UserIDFromCtx returns the authenticated user ID from the context.
// Returns 0 if not set (i.e., middleware was not applied).
func UserIDFromCtx(ctx context.Context) int64 {
	if v, ok := ctx.Value(ctxKeyUserID).(int64); ok {
		return v
	}
	return 0
}

// ClaimsFromCtx returns the full JWT claims from the context.
func ClaimsFromCtx(ctx context.Context) *jwt.Claims {
	if v, ok := ctx.Value(ctxKeyClaims).(*jwt.Claims); ok {
		return v
	}
	return nil
}

// bearerToken extracts the raw token from the Authorization header.
func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(h, "Bearer ")
}
