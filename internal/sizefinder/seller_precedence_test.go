package sizefinder

import (
	"context"
	"testing"
)

// A seller chart with labels that exist ONLY here ("P"/"Q") so a returned size
// proves the seller chart — not the standard ladder — backed the match.
func sellerTopChart() *SellerChart {
	return &SellerChart{
		GarmentType: GarmentTop, Gender: GenderFemale,
		Rows: []ChartRow{
			{GarmentType: GarmentTop, SizeLabel: "P", SortRank: 1, Measurement: "chest", MinMM: 900, MaxMM: 980},
			{GarmentType: GarmentTop, SizeLabel: "Q", SortRank: 2, Measurement: "chest", MinMM: 980, MaxMM: 1100},
		},
	}
}

func recSeller(t *testing.T, p FitProfile, title string, sc *SellerChart) Recommendation {
	t.Helper()
	r, err := newTestSvc(p, nil).Recommend(context.Background(), 1, title, sc)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	return r
}

// Seller chart present → match against it; source=seller, chart_approximate=false.
func TestRecommend_SellerChartWins(t *testing.T) {
	r := recSeller(t, FitProfile{ChestMM: mm(1050), Gender: GenderFemale}, "Basic Tişört", sellerTopChart())
	if r.Status != StatusOK || r.Size != "Q" {
		t.Fatalf("seller chart should map chest1050 → Q: got %+v", r)
	}
	if r.Source != SourceSeller || r.ChartApproximate {
		t.Fatalf("seller chart → source=seller + chart_approximate=false: got %+v", r)
	}
	if r.Confidence != ConfidenceDetailed {
		t.Fatalf("all-real → detailed: got %+v", r)
	}
}

// No seller chart → fall back to the standard baseline (source=standard, approx).
func TestRecommend_StandardFallback(t *testing.T) {
	r := recSeller(t, FitProfile{ChestMM: mm(1000), Gender: GenderFemale}, "Basic Tişört", nil)
	if r.Status != StatusOK || r.Source != SourceStandard || !r.ChartApproximate {
		t.Fatalf("nil seller chart → standard baseline: got %+v", r)
	}
	if r.Size == "P" || r.Size == "Q" {
		t.Fatalf("standard path must not use seller labels: got %+v", r)
	}
}

// A BASIC (estimated) profile is still warned even on a seller chart.
func TestRecommend_SellerChartBasicStillWarned(t *testing.T) {
	r := recSeller(t, FitProfile{
		HeightMM: gi(1650), WeightG: gi(60000), Gender: GenderFemale,
	}, "Basic Tişört", sellerTopChart())
	if r.Status != StatusOK || r.Source != SourceSeller || r.ChartApproximate {
		t.Fatalf("seller basic: source=seller + approx=false: got %+v", r)
	}
	if r.Confidence != ConfidenceBasic || len(r.Estimated) == 0 {
		t.Fatalf("estimated measurement must keep the BASIC warning: got %+v", r)
	}
}

// Unclassifiable title with NO seller chart → no_chart, empty source.
func TestRecommend_NoChartNoSource(t *testing.T) {
	r := recSeller(t, FitProfile{ChestMM: mm(1000)}, "Blender 600W", nil)
	if r.Status != StatusNoChart || r.Source != "" {
		t.Fatalf("no_chart must carry empty source: got %+v", r)
	}
}
