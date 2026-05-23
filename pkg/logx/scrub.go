package logx

import (
	"strings"
)

// MaskPhone masks all but the last 4 digits of a phone number string.
// "+905321234567" → "+90*****4567"
// Returns "***" for inputs too short to mask meaningfully.
func MaskPhone(s string) string {
	s = strings.TrimSpace(s)
	runes := []rune(s)
	n := len(runes)
	if n < 5 {
		return "***"
	}
	// Preserve up to 3 prefix chars and last 4 digits.
	prefix := 3
	if n <= prefix+4 {
		// Short number: keep first char, mask rest except last 4.
		visible := 4
		if n <= visible {
			return strings.Repeat("*", n)
		}
		return string(runes[:1]) + strings.Repeat("*", n-1-visible) + string(runes[n-visible:])
	}
	return string(runes[:prefix]) + strings.Repeat("*", n-prefix-4) + string(runes[n-4:])
}

// MaskEmail masks a local-part and domain, keeping the first and last character
// of each segment.
// "sefersalih017@gmail.com" → "s***7@g***l.com"
func MaskEmail(s string) string {
	at := strings.LastIndex(s, "@")
	if at <= 0 {
		return "***"
	}
	local := s[:at]
	domain := s[at+1:]

	dot := strings.LastIndex(domain, ".")
	var maskedDomain string
	if dot > 0 {
		maskedDomain = maskMiddle(domain[:dot]) + domain[dot:]
	} else {
		maskedDomain = maskMiddle(domain)
	}
	return maskMiddle(local) + "@" + maskedDomain
}

// maskMiddle keeps the first and last rune of s, replacing the middle with "*".
// Strings of length ≤ 2 are fully masked.
func maskMiddle(s string) string {
	runes := []rune(s)
	n := len(runes)
	switch {
	case n == 0:
		return ""
	case n <= 2:
		return strings.Repeat("*", n)
	default:
		return string(runes[:1]) + strings.Repeat("*", n-2) + string(runes[n-1:])
	}
}
