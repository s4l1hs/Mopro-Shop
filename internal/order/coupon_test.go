package order

import (
	"testing"
	"time"
)

func ptrInt(n int) *int { return &n }

func TestResolveCoupon(t *testing.T) {
	now := time.Date(2026, 6, 11, 12, 0, 0, 0, time.UTC)
	base := &Coupon{
		ID: 1, Code: "WELCOME10", Kind: "percent", PercentOff: 10,
		Active: true, StartsAt: now.Add(-24 * time.Hour), Market: "TR",
	}
	exp := now.Add(-time.Hour)
	future := now.Add(24 * time.Hour)

	// tierGated is a coupon requiring rank >= 3 (elite); 0/unset = rank 1 = everyone.
	tierGated := &Coupon{
		ID: 2, Code: "ELITE15", Kind: "percent", PercentOff: 15,
		Active: true, StartsAt: now.Add(-24 * time.Hour), Market: "TR", MinTierRank: 3,
	}

	tests := []struct {
		name        string
		coupon      *Coupon
		subtotal    int64
		redemptions int
		tierRank    int
		wantValid   bool
		wantReason  string
		wantDisc    int64
	}{
		{"nil coupon", nil, 10000, 0, 1, false, "not_found", 0},
		{"valid 10pct", base, 10000, 0, 1, true, "", 1000},
		{"valid rounds half up (buyer-favour)", &Coupon{Code: "X", PercentOff: 10, Active: true, StartsAt: now.Add(-time.Hour)}, 105, 0, 1, true, "", 11}, // (105*10+50)/100 = 11
		{"inactive", &Coupon{Code: "X", PercentOff: 10, Active: false, StartsAt: now.Add(-time.Hour)}, 10000, 0, 1, false, "inactive", 0},
		{"not started", &Coupon{Code: "X", PercentOff: 10, Active: true, StartsAt: future}, 10000, 0, 1, false, "not_started", 0},
		{"expired", &Coupon{Code: "X", PercentOff: 10, Active: true, StartsAt: now.Add(-time.Hour), ExpiresAt: &exp}, 10000, 0, 1, false, "expired", 0},
		{"below min basket", &Coupon{Code: "X", PercentOff: 10, Active: true, StartsAt: now.Add(-time.Hour), MinBasketMinor: 20000}, 10000, 0, 1, false, "min_basket", 0},
		{"exhausted", &Coupon{Code: "X", PercentOff: 10, Active: true, StartsAt: now.Add(-time.Hour), MaxRedemptions: ptrInt(5)}, 10000, 5, 1, false, "exhausted", 0},
		{"under max ok", &Coupon{Code: "X", PercentOff: 10, Active: true, StartsAt: now.Add(-time.Hour), MaxRedemptions: ptrInt(5)}, 10000, 4, 1, true, "", 1000},
		// Tier gate (migration 0106). Eligibility only — never alters the amount.
		{"backward-compat: rank-1 coupon, classic user", base, 10000, 0, 1, true, "", 1000},
		{"backward-compat: rank-1 coupon, guest rank-1", base, 10000, 0, 1, true, "", 1000},
		{"tier_locked: elite coupon, classic user", tierGated, 10000, 0, 1, false, "tier_locked", 0},
		{"tier_locked: elite coupon, gold user (rank 2)", tierGated, 10000, 0, 2, false, "tier_locked", 0},
		{"tier ok: elite coupon, elite user (rank 3)", tierGated, 10000, 0, 3, true, "", 1500},
		{"tier ok: elite coupon, above (rank 4)", tierGated, 10000, 0, 4, true, "", 1500},
		// Tier gate runs only AFTER the cheaper invalidations — a tier-eligible user
		// still fails an expired coupon, never sees "tier_locked" mask a real reason.
		{"expired beats tier for eligible user", &Coupon{Code: "X", PercentOff: 10, Active: true, StartsAt: now.Add(-time.Hour), ExpiresAt: &exp, MinTierRank: 3}, 10000, 0, 3, false, "expired", 0},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := resolveCoupon(tc.coupon, tc.subtotal, tc.redemptions, tc.tierRank, now)
			if got.Valid != tc.wantValid {
				t.Errorf("Valid: got %v want %v (reason %q)", got.Valid, tc.wantValid, got.Reason)
			}
			if got.Reason != tc.wantReason {
				t.Errorf("Reason: got %q want %q", got.Reason, tc.wantReason)
			}
			if got.DiscountMinor != tc.wantDisc {
				t.Errorf("DiscountMinor: got %d want %d", got.DiscountMinor, tc.wantDisc)
			}
		})
	}
}

// TestCouponStacksOnBasketDiscount verifies the per-unit charge a coupon produces
// when applied ON TOP of a basket discount — the exact math the order build uses,
// so it pins the display==charge contract and the cashback-on-discounted-price rule.
func TestCouponStacksOnBasketDiscount(t *testing.T) {
	const list int64 = 10000 // 100,00 ₺ unit
	basketPct := 20          // CT-09 seller basket discount
	couponPct := 10          // CT-03 coupon

	basketUnit := DiscountedUnitMinor(list, basketPct) // 8000
	if basketUnit != 8000 {
		t.Fatalf("basketUnit: got %d want 8000", basketUnit)
	}
	chargedUnit := DiscountedUnitMinor(basketUnit, couponPct) // 7200
	if chargedUnit != 7200 {
		t.Fatalf("chargedUnit: got %d want 7200", chargedUnit)
	}
	couponSlice := basketUnit - chargedUnit // 800
	if couponSlice != 800 {
		t.Fatalf("couponSlice: got %d want 800", couponSlice)
	}
	// commission/cashback derive from the FINAL charged unit (snapshot), so the
	// coupon discount propagates to fin-svc with no fin-svc change.
	const commBps = 1000 // 10%
	comm := chargedUnit * commBps / 10000
	if comm != 720 {
		t.Errorf("commission on charged unit: got %d want 720 (10%% of 7200)", comm)
	}
}

func TestNormalizeCouponCode(t *testing.T) {
	for in, want := range map[string]string{
		"  welcome10 ": "WELCOME10",
		"SAVE20":       "SAVE20",
		"":             "",
		"   ":          "",
	} {
		if got := NormalizeCouponCode(in); got != want {
			t.Errorf("NormalizeCouponCode(%q) = %q, want %q", in, got, want)
		}
	}
}
