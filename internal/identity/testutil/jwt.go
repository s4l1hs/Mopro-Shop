// Package testutil provides helpers for identity-related tests.
package testutil

import (
	"testing"

	identityjwt "github.com/mopro/platform/internal/identity/jwt"
)

// testSigningKey is a stable 32-byte key used only in tests.
// Never use in production — it is committed to source control.
var testSigningKey = []byte("mopro-test-signing-key-32-bytes!")

// IssueTestAccessToken issues a real HS256 JWT for the given userID and market.
// Tests that need an authenticated request context should call this to obtain a
// Bearer token and set: req.Header.Set("Authorization", "Bearer "+token).
//
// Usage:
//
//	token := testutil.IssueTestAccessToken(t, 42, "TR")
//	req.Header.Set("Authorization", "Bearer "+token)
func IssueTestAccessToken(t *testing.T, userID int64, market string) string {
	t.Helper()
	signer, err := identityjwt.NewHS256Signer(testSigningKey)
	if err != nil {
		t.Fatalf("testutil: NewHS256Signer: %v", err)
	}
	token, _, err := signer.IssueAccess(userID, market)
	if err != nil {
		t.Fatalf("testutil: IssueAccess(%d, %q): %v", userID, market, err)
	}
	return token
}

// TestSigner returns an identityjwt.Signer using the stable test signing key.
// Use this to create middleware in tests that validates tokens issued by IssueTestAccessToken.
func TestSigner(t *testing.T) *identityjwt.HS256Signer {
	t.Helper()
	signer, err := identityjwt.NewHS256Signer(testSigningKey)
	if err != nil {
		t.Fatalf("testutil: TestSigner: %v", err)
	}
	return signer
}
