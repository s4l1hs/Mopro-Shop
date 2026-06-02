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

// OptionalAuth is RequireAuth's permissive sibling: if a valid API-scope Bearer
// token is present it stores the user ID + claims in the context (so handlers can
// personalize the response), but a missing or invalid token is NOT an error — the
// request proceeds as a guest with UserIDFromCtx == 0. Used by public read
// endpoints that still want viewer-specific fields (e.g. reviews'
// votedByCurrentUser).
func OptionalAuth(signer jwt.Signer) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tok := bearerToken(r)
			if tok == "" {
				next.ServeHTTP(w, r)
				return
			}
			claims, err := signer.Verify(tok)
			if err != nil || claims.Scope != jwt.ScopeAPI {
				// Treat an unusable token as guest; do not reject.
				next.ServeHTTP(w, r)
				return
			}
			ctx := context.WithValue(r.Context(), ctxKeyUserID, claims.UserID)
			ctx = context.WithValue(ctx, ctxKeyClaims, claims)
			span := trace.SpanFromContext(ctx)
			span.SetAttributes(attribute.Int64("user_id", claims.UserID))
			ctx = logx.With(ctx, slog.Int64("user_id", claims.UserID))
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// ContextWithUserID returns a copy of ctx carrying the given authenticated user
// ID under the same key RequireAuth/OptionalAuth use. Useful for composing
// contexts in tests and internal callers that bypass the HTTP middleware.
func ContextWithUserID(ctx context.Context, userID int64) context.Context {
	return context.WithValue(ctx, ctxKeyUserID, userID)
}

// UserIDFromCtx returns the authenticated user ID from the context.
// Returns 0 if not set (i.e., middleware was not applied).
func UserIDFromCtx(ctx context.Context) int64 {
	if v, ok := ctx.Value(ctxKeyUserID).(int64); ok {
		return v
	}
	return 0
}

// bearerToken extracts the raw token from the Authorization header.
func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(h, "Bearer ")
}
