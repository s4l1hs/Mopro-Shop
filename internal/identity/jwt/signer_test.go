package jwt

// F-012 probe (TESTING_AUDIT): does IssueAccess produce distinct tokens for two
// issuances in the same wall-clock second? If not (no unique jti), two sessions are
// byte-identical and indistinguishable. See docs/audits/TESTING_AUDIT.md F-012.

import "testing"

var testKey = []byte("0123456789abcdef0123456789abcdef") // 32 bytes

// TestIssueAccess_SameSecond_DistinctJTI locks in the property that two access tokens
// issued for the same subject within the same second are distinct (carry a unique jti).
// Pre-fix this FAILED (claims were Subject+uid+mkt+scope+iat[sec]+exp[sec] with no jti
// → identical bytes); the jti fix in the same PR makes it pass.
func TestIssueAccess_SameSecond_DistinctJTI(t *testing.T) {
	signer, err := NewHS256Signer(testKey)
	if err != nil {
		t.Fatalf("NewHS256Signer: %v", err)
	}
	// Two issuances back-to-back → same wall-clock second (iat has 1s resolution).
	t1, _, err := signer.IssueAccess(42, "TR")
	if err != nil {
		t.Fatalf("IssueAccess #1: %v", err)
	}
	t2, _, err := signer.IssueAccess(42, "TR")
	if err != nil {
		t.Fatalf("IssueAccess #2: %v", err)
	}
	if t1 == t2 {
		t.Fatal("F-012: two same-second access tokens are byte-identical (no unique jti)")
	}
	c1, err := signer.Verify(t1)
	if err != nil {
		t.Fatalf("Verify t1: %v", err)
	}
	c2, err := signer.Verify(t2)
	if err != nil {
		t.Fatalf("Verify t2: %v", err)
	}
	if c1.ID == "" {
		t.Error("F-012: access token must carry a jti (RegisteredClaims.ID)")
	}
	if c1.ID == c2.ID {
		t.Errorf("F-012: jti must be unique per token; both are %q", c1.ID)
	}
	// Claims that SHOULD match (same subject/scope) — sanity that we didn't break identity.
	if c1.UserID != c2.UserID || c1.Scope != c2.Scope || c1.Market != c2.Market {
		t.Errorf("identity claims must be stable: %+v vs %+v", c1, c2)
	}
}

// TestIssueStepUp_DistinctJTI — same property for step-up tokens (they share issue()).
func TestIssueStepUp_SameSecond_DistinctJTI(t *testing.T) {
	signer, err := NewHS256Signer(testKey)
	if err != nil {
		t.Fatalf("NewHS256Signer: %v", err)
	}
	t1, _, _ := signer.IssueStepUp(7)
	t2, _, _ := signer.IssueStepUp(7)
	if t1 == t2 {
		t.Fatal("F-012: two same-second step-up tokens are byte-identical (no unique jti)")
	}
}
