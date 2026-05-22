package main

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/internal/identity/middleware"
	pkgcrypto "github.com/mopro/platform/pkg/crypto"
	"github.com/mopro/platform/pkg/httpx"
)

// authHandlers holds the identity.Service and registers all auth + me + device routes.
type authHandlers struct {
	svc identity.Service
	log *slog.Logger
}

// registerAuthRoutes adds all identity routes to mux.
// Routes that require JWT auth are wrapped with the RequireAuth middleware.
func (a *authHandlers) registerRoutes(mux *http.ServeMux, requireAuth func(http.Handler) http.Handler) {
	// ── Public auth routes (no JWT required) ─────────────────────────────────
	mux.Handle("POST /v1/auth/otp/request",
		httpTrace(http.HandlerFunc(a.handleRequestOTP)),
	)
	mux.Handle("POST /v1/auth/otp/verify",
		httpTrace(http.HandlerFunc(a.handleVerifyOTP)),
	)
	mux.Handle("POST /v1/auth/token/refresh",
		httpTrace(http.HandlerFunc(a.handleRefreshTokens)),
	)

	// ── Authenticated routes ──────────────────────────────────────────────────
	mux.Handle("POST /v1/auth/logout",
		httpTrace(requireAuth(http.HandlerFunc(a.handleLogout))),
	)
	mux.Handle("GET /v1/me",
		httpTrace(requireAuth(http.HandlerFunc(a.handleGetMe))),
	)
	mux.Handle("PATCH /v1/me",
		httpTrace(requireAuth(http.HandlerFunc(a.handleUpdateMe))),
	)
	mux.Handle("DELETE /v1/me",
		httpTrace(requireAuth(http.HandlerFunc(a.handleDeleteMe))),
	)
	mux.Handle("POST /v1/auth/step-up/request",
		httpTrace(requireAuth(http.HandlerFunc(a.handleRequestStepUpOTP))),
	)
	mux.Handle("POST /v1/auth/step-up/verify",
		httpTrace(requireAuth(http.HandlerFunc(a.handleVerifyStepUpOTP))),
	)
	mux.Handle("POST /v1/me/devices",
		httpTrace(requireAuth(http.HandlerFunc(a.handleRegisterDevice))),
	)
}

// httpTrace wraps a handler with the TraceAndLog middleware used by all routes.
func httpTrace(h http.Handler) http.Handler {
	return httpx.TraceAndLog(h)
}

// ── Handlers ──────────────────────────────────────────────────────────────────

func (a *authHandlers) handleRequestOTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Phone   string `json:"phone"`
		Purpose string `json:"purpose"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if req.Phone == "" {
		jsonError(w, "phone required", http.StatusBadRequest)
		return
	}
	if req.Purpose == "" {
		req.Purpose = identity.OTPPurposeLogin
	}
	if req.Purpose != identity.OTPPurposeLogin && req.Purpose != identity.OTPPurposeStepUp {
		jsonError(w, "purpose must be login or step_up", http.StatusBadRequest)
		return
	}

	clientIP := extractClientIP(r)
	if err := a.svc.RequestOTP(r.Context(), req.Phone, req.Purpose, clientIP); err != nil {
		a.writeIdentityError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *authHandlers) handleVerifyOTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Phone   string `json:"phone"`
		Code    string `json:"code"`
		Purpose string `json:"purpose"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if req.Phone == "" || req.Code == "" {
		jsonError(w, "phone and code required", http.StatusBadRequest)
		return
	}
	if req.Purpose == "" {
		req.Purpose = identity.OTPPurposeLogin
	}

	pair, err := a.svc.VerifyOTP(r.Context(), req.Phone, req.Purpose, req.Code)
	if err != nil {
		a.writeIdentityError(w, err)
		return
	}
	jsonOK(w, http.StatusOK, tokenPairResponse(pair))
}

func (a *authHandlers) handleRefreshTokens(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		jsonError(w, "refresh_token required", http.StatusBadRequest)
		return
	}

	pair, err := a.svc.RefreshTokens(r.Context(), req.RefreshToken)
	if err != nil {
		a.writeIdentityError(w, err)
		return
	}
	jsonOK(w, http.StatusOK, tokenPairResponse(pair))
}

func (a *authHandlers) handleLogout(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		jsonError(w, "refresh_token required", http.StatusBadRequest)
		return
	}
	if err := a.svc.Logout(r.Context(), req.RefreshToken); err != nil {
		a.writeIdentityError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *authHandlers) handleGetMe(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromCtx(r.Context())
	user, err := a.svc.GetMe(r.Context(), userID)
	if err != nil {
		a.writeIdentityError(w, err)
		return
	}
	jsonOK(w, http.StatusOK, userResponse(user))
}

func (a *authHandlers) handleUpdateMe(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromCtx(r.Context())
	var req struct {
		NameFirst *string `json:"name_first"`
		NameLast  *string `json:"name_last"`
		Email     *string `json:"email"`
		Locale    *string `json:"locale"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, "invalid JSON", http.StatusBadRequest)
		return
	}

	updates := identity.UserUpdates{
		Email:  req.Email,
		Locale: req.Locale,
	}
	// Merge NameFirst + NameLast into domain Name field.
	if req.NameFirst != nil || req.NameLast != nil {
		first := ""
		last := ""
		if req.NameFirst != nil {
			first = strings.TrimSpace(*req.NameFirst)
		}
		if req.NameLast != nil {
			last = strings.TrimSpace(*req.NameLast)
		}
		name := strings.TrimSpace(first + " " + last)
		updates.Name = &name
	}

	user, err := a.svc.UpdateMe(r.Context(), userID, updates)
	if err != nil {
		a.writeIdentityError(w, err)
		return
	}
	jsonOK(w, http.StatusOK, userResponse(user))
}

func (a *authHandlers) handleDeleteMe(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromCtx(r.Context())
	if err := a.svc.DeleteMe(r.Context(), userID); err != nil {
		a.writeIdentityError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *authHandlers) handleRequestStepUpOTP(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromCtx(r.Context())
	clientIP := extractClientIP(r)
	if err := a.svc.RequestStepUpOTP(r.Context(), userID, clientIP); err != nil {
		a.writeIdentityError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *authHandlers) handleVerifyStepUpOTP(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromCtx(r.Context())
	var req struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Code == "" {
		jsonError(w, "code required", http.StatusBadRequest)
		return
	}
	tok, err := a.svc.VerifyStepUpOTP(r.Context(), userID, req.Code)
	if err != nil {
		a.writeIdentityError(w, err)
		return
	}
	jsonOK(w, http.StatusOK, map[string]any{
		"step_up_token": tok.Token,
		"expires_in":    int(time.Until(tok.ExpiresAt).Seconds()),
	})
}

func (a *authHandlers) handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromCtx(r.Context())
	var req struct {
		FCMToken    string `json:"fcm_token"`
		DeviceModel string `json:"device_model"`
		OSVersion   string `json:"os_version"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.FCMToken == "" {
		jsonError(w, "fcm_token required", http.StatusBadRequest)
		return
	}
	dev, err := a.svc.RegisterDevice(r.Context(), userID, identity.DeviceInfo{
		FCMToken:    req.FCMToken,
		DeviceModel: req.DeviceModel,
		OSVersion:   req.OSVersion,
	})
	if err != nil {
		a.writeIdentityError(w, err)
		return
	}
	jsonOK(w, http.StatusCreated, map[string]any{
		"id":            dev.ID,
		"fcm_token":     dev.FCMToken,
		"device_model":  dev.DeviceModel,
		"os_version":    dev.OSVersion,
		"registered_at": dev.RegisteredAt,
	})
}

// ── Response helpers ──────────────────────────────────────────────────────────

func tokenPairResponse(p identity.TokenPair) map[string]any {
	return map[string]any{
		"access_token":       p.AccessToken,
		"token_type":         "Bearer",
		"expires_in":         int(15 * 60), // 15 min access token TTL
		"refresh_token":      p.RefreshToken,
		"refresh_expires_at": p.RefreshExpiresAt,
	}
}

func userResponse(u identity.User) map[string]any {
	first, last := splitName(u.Name)
	// Decrypt phone for masking; on error, show generic mask.
	maskedPhone := "***"
	if plain, err := pkgcrypto.DecryptPII(u.PhoneEnc); err == nil {
		maskedPhone = identity.MaskPhone(plain)
	}
	return map[string]any{
		"id":         u.ID,
		"phone":      maskedPhone,
		"name_first": first,
		"name_last":  last,
		"locale":     u.Locale,
		"created_at": u.CreatedAt,
		"updated_at": u.UpdatedAt,
	}
}

// splitName splits "Ahmet Yılmaz" → ("Ahmet", "Yılmaz").
// For a single-word name, last is empty.
func splitName(name string) (first, last string) {
	parts := strings.SplitN(strings.TrimSpace(name), " ", 2)
	if len(parts) == 0 {
		return "", ""
	}
	first = parts[0]
	if len(parts) == 2 {
		last = parts[1]
	}
	return first, last
}

// writeIdentityError maps identity domain errors to HTTP status codes.
func (a *authHandlers) writeIdentityError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, identity.ErrOTPNotFound):
		jsonError(w, "otp_not_found", http.StatusNotFound)
	case errors.Is(err, identity.ErrOTPExpired):
		jsonError(w, "otp_expired", http.StatusUnprocessableEntity)
	case errors.Is(err, identity.ErrOTPInvalid):
		jsonError(w, "otp_invalid", http.StatusUnprocessableEntity)
	case errors.Is(err, identity.ErrOTPAlreadyUsed):
		jsonError(w, "otp_already_used", http.StatusConflict)
	case errors.Is(err, identity.ErrOTPRateLimitExceeded):
		w.Header().Set("Retry-After", "60")
		jsonError(w, "rate_limit_exceeded", http.StatusTooManyRequests)
	case errors.Is(err, identity.ErrOTPVerifyLocked):
		w.Header().Set("Retry-After", "3600")
		jsonError(w, "phone_locked", http.StatusLocked)
	case errors.Is(err, identity.ErrTokenNotFound),
		errors.Is(err, identity.ErrTokenExpired),
		errors.Is(err, identity.ErrTokenRevoked):
		jsonError(w, "token_invalid", http.StatusUnauthorized)
	case errors.Is(err, identity.ErrTokenFamilyRevoked):
		jsonError(w, "token_family_revoked", http.StatusUnauthorized)
	case errors.Is(err, identity.ErrUserNotFound):
		jsonError(w, "user_not_found", http.StatusNotFound)
	case errors.Is(err, identity.ErrUserSuspended):
		jsonError(w, "account_suspended", http.StatusForbidden)
	case errors.Is(err, identity.ErrUserDeleted):
		jsonError(w, "account_deleted", http.StatusGone)
	case errors.Is(err, identity.ErrInvalidPhone):
		jsonError(w, "invalid_phone", http.StatusBadRequest)
	case errors.Is(err, identity.ErrInvalidEmail):
		jsonError(w, "invalid_email", http.StatusBadRequest)
	case errors.Is(err, identity.ErrInvalidLocale):
		jsonError(w, "invalid_locale", http.StatusBadRequest)
	case errors.Is(err, identity.ErrSMSSendFailed):
		jsonError(w, "sms_send_failed", http.StatusServiceUnavailable)
	default:
		a.log.Error("auth: unhandled error", "err", err)
		jsonError(w, "internal_error", http.StatusInternalServerError)
	}
}

// extractClientIP returns the real client IP, preferring CF-Connecting-IP (set by CloudFlare).
func extractClientIP(r *http.Request) string {
	if cf := r.Header.Get("CF-Connecting-IP"); cf != "" {
		return cf
	}
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.SplitN(xff, ",", 2)[0]
	}
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	return host
}

