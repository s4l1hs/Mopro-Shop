package cashback

import (
	"errors"
	"testing"
)

// ── validation table ──────────────────────────────────────────────────────────

func TestComputePlanTerms_ValidationTable(t *testing.T) {
	cases := []struct {
		name      string
		price     int64
		bps       int
		wantT     int
		wantM     int64
		wantMLast int64
	}{
		{"10kTL_2000bps", 1_000_000, 2000, 78, 12_820, 12_860},
		{"10kTL_1000bps", 1_000_000, 1000, 156, 6_410, 6_450},
		{"10kTL_800bps", 1_000_000, 800, 195, 5_128, 5_168},
		{"250TL_1500bps", 25_000, 1500, 104, 240, 280},
		{"999.99TL_2000bps", 99_999, 2000, 78, 1_282, 1_285},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ComputePlanTerms(tc.price, tc.bps)
			if err != nil {
				t.Fatalf("ComputePlanTerms(%d, %d): unexpected error: %v", tc.price, tc.bps, err)
			}
			if got.TotalMonths != tc.wantT {
				t.Errorf("TotalMonths: got %d, want %d", got.TotalMonths, tc.wantT)
			}
			if got.MonthlyAmountMinor != tc.wantM {
				t.Errorf("MonthlyAmountMinor: got %d, want %d", got.MonthlyAmountMinor, tc.wantM)
			}
			if got.MonthlyAmountLastMinor != tc.wantMLast {
				t.Errorf("MonthlyAmountLastMinor: got %d, want %d", got.MonthlyAmountLastMinor, tc.wantMLast)
			}
			sum := int64(got.TotalMonths-1)*got.MonthlyAmountMinor + got.MonthlyAmountLastMinor
			if sum != tc.price {
				t.Errorf("principal coverage: (T-1)*M + M_last = %d, want %d", sum, tc.price)
			}
		})
	}
}

// ── boundary / error cases ────────────────────────────────────────────────────

func TestComputePlanTerms_Errors(t *testing.T) {
	t.Run("price_zero_rejected", func(t *testing.T) {
		_, err := ComputePlanTerms(0, 2000)
		if !errors.Is(err, ErrInvalidPlanInput) {
			t.Errorf("want ErrInvalidPlanInput, got %v", err)
		}
	})
	t.Run("price_negative_rejected", func(t *testing.T) {
		_, err := ComputePlanTerms(-1, 2000)
		if !errors.Is(err, ErrInvalidPlanInput) {
			t.Errorf("want ErrInvalidPlanInput, got %v", err)
		}
	})
	t.Run("price_over_limit_rejected", func(t *testing.T) {
		_, err := ComputePlanTerms(int64(1e14)+1, 2000)
		if !errors.Is(err, ErrInvalidPlanInput) {
			t.Errorf("want ErrInvalidPlanInput, got %v", err)
		}
	})
	t.Run("bps_below_min_rejected", func(t *testing.T) {
		_, err := ComputePlanTerms(1_000_000, 99)
		if !errors.Is(err, ErrInvalidPlanInput) {
			t.Errorf("want ErrInvalidPlanInput for bps=99, got %v", err)
		}
	})
	t.Run("bps_above_max_rejected", func(t *testing.T) {
		_, err := ComputePlanTerms(1_000_000, 10001)
		if !errors.Is(err, ErrInvalidPlanInput) {
			t.Errorf("want ErrInvalidPlanInput for bps=10001, got %v", err)
		}
	})
	t.Run("degenerate_monthly_zero_rejected", func(t *testing.T) {
		// price=1, bps=10000: M = (1*10000)/156000 = 0 → degenerate schedule
		_, err := ComputePlanTerms(1, 10000)
		if !errors.Is(err, ErrInvalidPlanInput) {
			t.Errorf("want ErrInvalidPlanInput for degenerate schedule, got %v", err)
		}
	})
}

func TestComputePlanTerms_AcceptedBoundaries(t *testing.T) {
	t.Run("price_at_limit_accepted", func(t *testing.T) {
		got, err := ComputePlanTerms(int64(1e14), 100)
		if err != nil {
			t.Fatalf("want success for price=1e14, got %v", err)
		}
		if got.TotalMonths != 1560 {
			t.Errorf("TotalMonths: got %d, want 1560", got.TotalMonths)
		}
		sum := int64(got.TotalMonths-1)*got.MonthlyAmountMinor + got.MonthlyAmountLastMinor
		if sum != int64(1e14) {
			t.Errorf("principal coverage failed: %d != 1e14", sum)
		}
	})
	t.Run("bps_at_min_accepted", func(t *testing.T) {
		_, err := ComputePlanTerms(1_000_000, 100)
		if err != nil {
			t.Errorf("want success for bps=100, got %v", err)
		}
	})
	t.Run("bps_at_max_accepted", func(t *testing.T) {
		got, err := ComputePlanTerms(1_000_000, 10000)
		if err != nil {
			t.Fatalf("want success for bps=10000, got %v", err)
		}
		// T = 156000/10000 = 15
		if got.TotalMonths != 15 {
			t.Errorf("TotalMonths: got %d, want 15", got.TotalMonths)
		}
	})
}

// ── InstallmentAmount ─────────────────────────────────────────────────────────

func TestInstallmentAmount(t *testing.T) {
	terms := PlanTerms{TotalMonths: 78, MonthlyAmountMinor: 12820, MonthlyAmountLastMinor: 12860}

	cases := []struct {
		n    int
		want int64
	}{
		{1, 12820},
		{40, 12820},
		{77, 12820},
		{78, 12860},
		{0, 0},  // out of range — below
		{79, 0}, // out of range — above
		{-1, 0}, // out of range — negative
	}
	for _, tc := range cases {
		got := InstallmentAmount(terms, tc.n)
		if got != tc.want {
			t.Errorf("InstallmentAmount(terms, %d) = %d, want %d", tc.n, got, tc.want)
		}
	}
}
