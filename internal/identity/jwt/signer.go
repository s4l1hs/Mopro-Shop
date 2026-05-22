// Package jwt provides JWT signing and verification for the identity module.
// Scope values: "api" for access tokens, "high_sensitivity" for step-up tokens.
package jwt

import (
	"errors"
	"fmt"
	"time"

	libjwt "github.com/golang-jwt/jwt/v5"
)

// Signer signs and verifies JWTs for the identity module.
type Signer interface {
	// IssueAccess issues an access token (HS256, 15-minute TTL, scope="api").
	IssueAccess(userID int64, market string) (token string, expiresAt time.Time, err error)
	// IssueStepUp issues a step-up token (HS256, 5-minute TTL, scope="high_sensitivity").
	IssueStepUp(userID int64) (token string, expiresAt time.Time, err error)
	// Verify validates the token and returns the embedded claims.
	Verify(token string) (*Claims, error)
}

// Claims are the custom claims embedded in every Mopro JWT.
type Claims struct {
	UserID int64  `json:"uid"`
	Market string `json:"mkt,omitempty"`
	Scope  string `json:"scope"`
	libjwt.RegisteredClaims
}

// AccessTTL and StepUpTTL are the fixed token lifetimes (CLAUDE.md § 4.2 auth spec).
const (
	AccessTTL  = 15 * time.Minute
	StepUpTTL  = 5 * time.Minute
	ScopeAPI   = "api"
	ScopeStepUp = "high_sensitivity"
)

// HS256Signer implements Signer using HMAC-SHA256.
type HS256Signer struct {
	key []byte
}

// NewHS256Signer creates a signer using the given HMAC-SHA256 key material.
// key must be at least 32 bytes; the caller loads it from JWT_SIGNING_KEY env.
func NewHS256Signer(key []byte) (*HS256Signer, error) {
	if len(key) < 32 {
		return nil, errors.New("jwt: signing key must be at least 32 bytes")
	}
	cp := make([]byte, len(key))
	copy(cp, key)
	return &HS256Signer{key: cp}, nil
}

func (s *HS256Signer) IssueAccess(userID int64, market string) (string, time.Time, error) {
	return s.issue(userID, market, ScopeAPI, AccessTTL)
}

func (s *HS256Signer) IssueStepUp(userID int64) (string, time.Time, error) {
	return s.issue(userID, "", ScopeStepUp, StepUpTTL)
}

func (s *HS256Signer) issue(userID int64, market, scope string, ttl time.Duration) (string, time.Time, error) {
	now := time.Now()
	exp := now.Add(ttl)
	claims := Claims{
		UserID: userID,
		Market: market,
		Scope:  scope,
		RegisteredClaims: libjwt.RegisteredClaims{
			Subject:   fmt.Sprintf("%d", userID),
			IssuedAt:  libjwt.NewNumericDate(now),
			ExpiresAt: libjwt.NewNumericDate(exp),
		},
	}
	tok := libjwt.NewWithClaims(libjwt.SigningMethodHS256, claims)
	signed, err := tok.SignedString(s.key)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("jwt: sign: %w", err)
	}
	return signed, exp, nil
}

func (s *HS256Signer) Verify(token string) (*Claims, error) {
	claims := &Claims{}
	tok, err := libjwt.ParseWithClaims(token, claims, func(t *libjwt.Token) (any, error) {
		if _, ok := t.Method.(*libjwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("jwt: unexpected signing method %v", t.Header["alg"])
		}
		return s.key, nil
	})
	if err != nil || !tok.Valid {
		return nil, errors.New("jwt: invalid or expired token")
	}
	return claims, nil
}
