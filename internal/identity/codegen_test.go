//go:build !integration

package identity

// Whitebox test — package identity (not identity_test) so generateOTPCode /
// formatOTP are accessible.
//
// The OTP code's *uniformity* is crypto/rand.Int's guarantee (rejection
// sampling over [0, 1_000_000) — no modulo bias), not this package's logic, so
// it is deliberately NOT asserted here: a chi-square goodness-of-fit over a real
// random source false-fails at its alpha rate *by definition* (the old p=0.05
// test flaked ~5% of `make test` runs — closes flake TestProperty_OTPCodeDistribution).
// What this package actually owns — the bound and the zero-padded 6-digit format
// — is pinned deterministically below.

import (
	"strconv"
	"testing"
)

func TestOTPCode_Format(t *testing.T) {
	// Deterministic format cases, incl. the zero-padding boundaries a random
	// sample could miss (a "%d" regression would drop leading zeros).
	cases := []struct {
		n    int64
		want string
	}{
		{0, "000000"},
		{7, "000007"},
		{42, "000042"},
		{1000, "001000"},
		{123456, "123456"},
		{999999, "999999"},
	}
	for _, c := range cases {
		if got := formatOTP(c.n); got != c.want {
			t.Errorf("formatOTP(%d) = %q, want %q", c.n, got, c.want)
		}
	}

	// Live generator: every draw is a 6-digit numeric string in [0, 1_000_000).
	// The assertion holds for *every* output, so this never flakes (unlike the
	// removed chi-square uniformity test).
	for i := 0; i < 1000; i++ {
		code, err := generateOTPCode()
		if err != nil {
			t.Fatalf("generateOTPCode[%d]: %v", i, err)
		}
		if len(code) != 6 {
			t.Fatalf("code %q: want 6 digits, got %d", code, len(code))
		}
		if n, err := strconv.Atoi(code); err != nil || n < 0 || n > 999999 {
			t.Fatalf("code %q: not a 6-digit number in [0, 999999]", code)
		}
	}
}
