package logx

import (
	"math/rand"
	"strings"
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// ── MaskPhone unit tests ──────────────────────────────────────────────────────

func TestMaskPhone_TRFormat(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"+905321234567", "+90******4567"}, // 13 chars: 3 prefix + 6 stars + 4 suffix
		{"+905001234567", "+90******4567"}, // 13 chars
		{"+9055512345", "+90****2345"},     // 11 chars: 3 prefix + 4 stars + 4 suffix
		{"12345", "12345"},                 // 5 chars, too short to mask between prefix and suffix
		{"123", "***"},
	}
	for _, c := range cases {
		got := MaskPhone(c.in)
		if got != c.want {
			t.Errorf("MaskPhone(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestMaskPhone_Short(t *testing.T) {
	if MaskPhone("ab") != "***" {
		t.Errorf("short input should return ***")
	}
	if MaskPhone("") != "***" {
		t.Errorf("empty input should return ***")
	}
}

// TestProperty_MaskPhone_LastFourPreserved verifies that MaskPhone always
// preserves the last 4 digits of any numeric phone string long enough to mask.
func TestProperty_MaskPhone_LastFourPreserved(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(42)) //nolint:gosec // G404: math/rand for deterministic property test seeding

	properties := gopter.NewProperties(params)

	properties.Property("last 4 digits preserved in masked output", prop.ForAll(
		func(digits string) bool {
			phone := "+90" + digits
			masked := MaskPhone(phone)
			if masked == "***" {
				return true // too short, skip
			}
			// Last 4 runes of phone must appear at end of masked output.
			phoneRunes := []rune(phone)
			maskedRunes := []rune(masked)
			if len(phoneRunes) < 4 || len(maskedRunes) < 4 {
				return true
			}
			last4phone := string(phoneRunes[len(phoneRunes)-4:])
			last4masked := string(maskedRunes[len(maskedRunes)-4:])
			return last4phone == last4masked
		},
		// Generate 7–10 digit strings to simulate phone suffixes.
		gen.RegexMatch(`[0-9]{7,10}`),
	))

	properties.TestingRun(t)
}

// TestProperty_MaskPhone_NoFullDigitLeak verifies that MaskPhone never emits
// more than 4 consecutive digits for inputs longer than 8 chars.
func TestProperty_MaskPhone_NoFullDigitLeak(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 1000
	params.Rng = rand.New(rand.NewSource(42)) //nolint:gosec // G404: math/rand for deterministic property test seeding

	properties := gopter.NewProperties(params)

	properties.Property("no run of >4 consecutive digits beyond last-4 position", prop.ForAll(
		func(digits string) bool {
			phone := "+90" + digits
			masked := MaskPhone(phone)
			if masked == "***" {
				return true
			}
			maskedRunes := []rune(masked)
			if len(maskedRunes) < 5 {
				return true
			}
			// Strip last 4 characters (the preserved suffix) from the check.
			prefix := string(maskedRunes[:len(maskedRunes)-4])
			// prefix must not contain more than 3 consecutive digits.
			run := 0
			for _, r := range prefix {
				if r >= '0' && r <= '9' {
					run++
					if run > 3 {
						return false
					}
				} else {
					run = 0
				}
			}
			return true
		},
		gen.RegexMatch(`[0-9]{8,12}`),
	))

	properties.TestingRun(t)
}

// ── MaskEmail unit tests ──────────────────────────────────────────────────────

func TestMaskEmail_Standard(t *testing.T) {
	cases := []struct {
		in      string
		wantAt  bool // output must contain '@'
		noLocal bool // local part (before @) must not be the original
	}{
		{"sefersalih017@gmail.com", true, true},
		{"a@b.com", true, false}, // single-char local — fully masked
		{"ab@cd.com", true, true},
		{"user@example.org", true, true},
	}
	for _, c := range cases {
		got := MaskEmail(c.in)
		if c.wantAt && !strings.Contains(got, "@") {
			t.Errorf("MaskEmail(%q) = %q: missing @", c.in, got)
		}
		at := strings.LastIndex(c.in, "@")
		origLocal := c.in[:at]
		gotLocal := ""
		if i := strings.LastIndex(got, "@"); i > 0 {
			gotLocal := got[:i]
			if c.noLocal && gotLocal == origLocal && len(origLocal) > 2 {
				t.Errorf("MaskEmail(%q) = %q: local part not masked", c.in, got)
			}
			_ = gotLocal
		}
		_ = gotLocal
	}
}

func TestMaskEmail_NoAt(t *testing.T) {
	if MaskEmail("notanemail") != "***" {
		t.Errorf("email without @ should return ***")
	}
}
