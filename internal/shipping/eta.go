package shipping

import (
	"context"
	"strings"
)

// EstimateETA computes a cheap, table-driven pre-purchase delivery estimate.
// Resolution: a concrete origin×dest transit row when both cities resolve to
// zones (Confident=true); otherwise the market's conservative national fallback
// (Confident=false); otherwise ETAResult{} when even the fallback is missing.
// No carrier call — only ref_schema lookups. Reference-data lookup failures
// degrade to the fallback rather than erroring the PDP; only an unexpected DB
// error propagates.
func (s *shippingService) EstimateETA(ctx context.Context, market, originCity string, destCity *string) (ETAResult, error) {
	origin := normalizeCity(originCity)
	if origin != "" && destCity != nil {
		if dest := normalizeCity(*destCity); dest != "" {
			minD, maxD, found, err := s.repo.LookupTransit(ctx, market, origin, dest)
			if err != nil {
				return ETAResult{}, err
			}
			if found {
				return ETAResult{MinDays: minD, MaxDays: maxD, Confident: true}, nil
			}
		}
	}

	minD, maxD, found, err := s.repo.LookupTransitDefault(ctx, market)
	if err != nil {
		return ETAResult{}, err
	}
	if !found {
		return ETAResult{}, nil // no data → caller omits the line
	}
	return ETAResult{MinDays: minD, MaxDays: maxD, Confident: false}, nil
}

// turkishFold maps Turkish-specific letters to their ASCII counterparts so a
// user-supplied destination city ("İstanbul", "Muğla") matches the ASCII keys
// seeded in ref_schema.shipping_zones. Applied BEFORE ToLower because ToLower on
// 'İ' yields an i + combining dot, not a plain 'i'.
var turkishFold = strings.NewReplacer(
	"ç", "c", "Ç", "c",
	"ğ", "g", "Ğ", "g",
	"ı", "i", "İ", "i", "I", "i",
	"ö", "o", "Ö", "o",
	"ş", "s", "Ş", "s",
	"ü", "u", "Ü", "u",
)

// normalizeCity folds a free-text city to the normalized ASCII key convention
// used by ref_schema.shipping_zones (lower, ascii-folded, trimmed).
func normalizeCity(city string) string {
	return strings.ToLower(turkishFold.Replace(strings.TrimSpace(city)))
}
