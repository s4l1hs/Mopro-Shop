package sizefinder

import (
	"context"
	"testing"
)

func gi(v int) *int { return &v }

// estimateMeasurement: real inputs produce mid-chart values; missing inputs / no
// gender → not estimable.
func TestEstimateMeasurement(t *testing.T) {
	male := FitProfile{HeightMM: gi(1800), WeightG: gi(80000), Gender: GenderMale}
	chest, ok := estimateMeasurement(male, "chest")
	if !ok || chest < 940 || chest > 1100 {
		t.Fatalf("male 80kg/180cm chest: ok=%v mm=%d (want ~L band)", ok, chest)
	}
	if _, ok := estimateMeasurement(male, "inseam"); ok {
		t.Error("inseam is not chart-used → should not estimate")
	}
	noGender := FitProfile{HeightMM: gi(1700), WeightG: gi(60000), Gender: GenderUnspecified}
	if _, ok := estimateMeasurement(noGender, "chest"); ok {
		t.Error("unspecified gender → not estimable")
	}
	noWeight := FitProfile{HeightMM: gi(1700), Gender: GenderFemale}
	if _, ok := estimateMeasurement(noWeight, "chest"); ok {
		t.Error("missing weight → not estimable")
	}
}

// rb runs Recommend (basic-mode helper, mirrors rec()).
func rb(t *testing.T, p FitProfile, title string) Recommendation {
	t.Helper()
	r, err := newTestSvc(p, nil).Recommend(context.Background(), 1, title, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	return r
}

func TestRecommend_TierDetailed(t *testing.T) {
	r := rb(t, FitProfile{ChestMM: mm(970)}, "Basic Tişört")
	if r.Status != StatusOK || r.Confidence != ConfidenceDetailed || len(r.Estimated) != 0 {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_TierBasic(t *testing.T) {
	// height+weight+gender only → chest estimated → BASIC.
	r := rb(t, FitProfile{
		HeightMM: gi(1800), WeightG: gi(80000), Gender: GenderMale,
	}, "Basic Tişört")
	if r.Status != StatusOK || r.Confidence != ConfidenceBasic || r.Size == "" {
		t.Fatalf("status/confidence/size: got %+v", r)
	}
	if len(r.Estimated) != 1 || r.Estimated[0] != "chest" {
		t.Fatalf("estimated: got %+v", r)
	}
}

func TestRecommend_TierPartial(t *testing.T) {
	// real waist + estimable hip → BASIC, hip estimated.
	r := rb(t, FitProfile{
		WaistMM: mm(810), HeightMM: gi(1750), WeightG: gi(75000), Gender: GenderFemale,
	}, "Slim Fit Pantolon")
	if r.Status != StatusOK || r.Confidence != ConfidenceBasic {
		t.Fatalf("status/confidence: got %+v", r)
	}
	if len(r.Estimated) != 1 || r.Estimated[0] != "hip" {
		t.Fatalf("estimated: got %+v", r)
	}
}

func TestRecommend_TierDetailedMulti(t *testing.T) {
	r := rb(t, FitProfile{WaistMM: mm(810), HipMM: mm(1010)}, "Slim Fit Pantolon")
	if r.Status != StatusOK || r.Confidence != ConfidenceDetailed || len(r.Estimated) != 0 {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_TierNoneUnspecifiedGender(t *testing.T) {
	r := rb(t, FitProfile{HeightMM: gi(1700), WeightG: gi(60000)}, "Basic Tişört")
	if r.Status != StatusIncompleteProfile || r.Size != "" || r.Confidence != "" {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_TierNoneMissingWeight(t *testing.T) {
	r := rb(t, FitProfile{HeightMM: gi(1700), Gender: GenderMale}, "Basic Tişört")
	if r.Status != StatusIncompleteProfile {
		t.Fatalf("got %+v", r)
	}
}

func TestUpsertProfile_BasicValidation(t *testing.T) {
	svc := newTestSvc(FitProfile{}, nil)
	ctx := context.Background()
	if err := svc.UpsertProfile(ctx, FitProfile{UserID: 1, WeightG: gi(80)}); err == nil {
		t.Error("g-typo weight (80g) should be rejected")
	}
	if err := svc.UpsertProfile(ctx, FitProfile{UserID: 1, Gender: "other"}); err == nil {
		t.Error("unknown gender should be rejected")
	}
	if err := svc.UpsertProfile(ctx, FitProfile{
		UserID: 1, HeightMM: gi(1800), WeightG: gi(80000), Gender: GenderMale,
	}); err != nil {
		t.Errorf("valid basic profile rejected: %v", err)
	}
}
