//go:build !integration

package identity

// Whitebox test — package identity (not identity_test) so generateOTPCode is accessible.
// 100,000 samples; chi-square goodness-of-fit for uniform distribution.
// Plan requirement A: chi-square p-value > 0.05.

import (
	"math"
	"testing"
)

// chi2CriticalDF9_p005 is the chi-square critical value for df=9 at p=0.05.
// If the computed statistic exceeds this, the null hypothesis of uniformity is rejected.
const chi2CriticalDF9_p005 = 16.919

// TestProperty_OTPCodeDistribution calls generateOTPCode 100,000 times and verifies:
//  1. Every code is exactly 6 decimal digits.
//  2. The leading-digit distribution is uniform (chi-square, p > 0.05).
func TestProperty_OTPCodeDistribution(t *testing.T) {
	const n = 100_000

	digitCounts := make([]float64, 10) // leading digit 0-9
	for i := 0; i < n; i++ {
		code, err := generateOTPCode()
		if err != nil {
			t.Fatalf("generateOTPCode[%d]: %v", i, err)
		}
		if len(code) != 6 {
			t.Fatalf("code[%d] = %q: expected 6 chars, got %d", i, code, len(code))
		}
		for _, ch := range code {
			if ch < '0' || ch > '9' {
				t.Fatalf("code[%d] = %q: non-digit character %q", i, code, ch)
				break
			}
		}
		leadDigit := int(code[0] - '0')
		digitCounts[leadDigit]++
	}

	// Chi-square goodness-of-fit over leading digit (10 cells, expected = n/10).
	expected := float64(n) / 10
	chi2 := 0.0
	for d, obs := range digitCounts {
		diff := obs - expected
		chi2 += diff * diff / expected
		t.Logf("digit %d: observed=%.0f expected=%.0f dev=%.3f", d, obs, expected, math.Abs(diff)/expected*100)
	}

	// p-value approximation via chi-square CDF (df=9).
	// We use a simple check against the 5% critical value.
	t.Logf("chi2 = %.4f (critical at p=0.05, df=9: %.3f)", chi2, chi2CriticalDF9_p005)
	if chi2 > chi2CriticalDF9_p005 {
		t.Errorf("chi-square test FAILED: chi2=%.4f > critical=%.3f — OTP generator is NOT uniform at p=0.05",
			chi2, chi2CriticalDF9_p005)
	} else {
		t.Logf("PASS: chi2=%.4f < %.3f — OTP generator is uniform at p > 0.05 (n=%d)", chi2, chi2CriticalDF9_p005, n)
	}
}
