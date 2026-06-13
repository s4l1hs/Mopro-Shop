package sizefinder

import (
	"context"
	"testing"
)

type fakeRepo struct {
	profile    FitProfile
	profileErr error
	charts     map[GarmentType][]ChartRow
}

func (f *fakeRepo) UpsertProfile(context.Context, FitProfile) error { return nil }
func (f *fakeRepo) GetProfile(context.Context, int64) (FitProfile, error) {
	return f.profile, f.profileErr
}
func (f *fakeRepo) ChartFor(_ context.Context, g GarmentType) ([]ChartRow, error) {
	return f.charts[g], nil
}

func mm(v int) *int { return &v }

// topChart mirrors the 0096 seed for tops.
func topChart() []ChartRow {
	ranges := [][3]int{{1, 820, 880}, {2, 880, 940}, {3, 940, 1000}, {4, 1000, 1080}, {5, 1080, 1160}, {6, 1160, 1260}}
	labels := []string{"XS", "S", "M", "L", "XL", "XXL"}
	out := make([]ChartRow, 0, 6)
	for i, r := range ranges {
		out = append(out, ChartRow{GarmentType: GarmentTop, SizeLabel: labels[i], SortRank: r[0], Measurement: "chest", MinMM: r[1], MaxMM: r[2]})
	}
	return out
}

func bottomChart() []ChartRow {
	labels := []string{"XS", "S", "M", "L", "XL", "XXL"}
	waist := [][3]int{{1, 660, 720}, {2, 720, 780}, {3, 780, 840}, {4, 840, 920}, {5, 920, 1000}, {6, 1000, 1100}}
	hip := [][3]int{{1, 860, 920}, {2, 920, 980}, {3, 980, 1040}, {4, 1040, 1120}, {5, 1120, 1200}, {6, 1200, 1300}}
	var out []ChartRow
	for i := range labels {
		out = append(out,
			ChartRow{GarmentType: GarmentBottom, SizeLabel: labels[i], SortRank: waist[i][0], Measurement: "waist", MinMM: waist[i][1], MaxMM: waist[i][2]},
			ChartRow{GarmentType: GarmentBottom, SizeLabel: labels[i], SortRank: hip[i][0], Measurement: "hip", MinMM: hip[i][1], MaxMM: hip[i][2]})
	}
	return out
}

func newTestSvc(p FitProfile, perr error) Service {
	return NewService(&fakeRepo{profile: p, profileErr: perr,
		charts: map[GarmentType][]ChartRow{GarmentTop: topChart(), GarmentBottom: bottomChart()}})
}

func TestClassifyTitle(t *testing.T) {
	cases := []struct {
		title string
		want  GarmentType
		ok    bool
	}{
		{"Nike Dri-FIT Tişört", GarmentTop, true},
		{"Yazlık Çiçekli Elbise", GarmentDress, true},
		{"Slim Fit Pantolon", GarmentBottom, true},
		{"Pileli Mini Etek", GarmentSkirt, true},
		{"Şişme Mont", GarmentOuterwear, true},
		{"Spor Elbise Askılı", GarmentDress, true}, // dress beats generic words
		{"Paslanmaz Çelik Blender", "", false},     // non-apparel → no match
		{"Eşofman Altı Jogger", GarmentBottom, true},
	}
	for _, tc := range cases {
		got, ok := ClassifyTitle(tc.title)
		if got != tc.want || ok != tc.ok {
			t.Errorf("%q: want (%s,%v) got (%s,%v)", tc.title, tc.want, tc.ok, got, ok)
		}
	}
}

func TestRecommend_Statuses(t *testing.T) {
	ctx := context.Background()

	t.Run("non-apparel → no_chart", func(t *testing.T) {
		rec, err := newTestSvc(FitProfile{}, nil).Recommend(ctx, 1, "Blender 600W")
		if err != nil || rec.Status != StatusNoChart || !rec.ChartApproximate {
			t.Fatalf("got %+v err=%v", rec, err)
		}
	})
	t.Run("no profile → no_profile + missing list", func(t *testing.T) {
		rec, err := newTestSvc(FitProfile{}, ErrProfileNotFound).Recommend(ctx, 1, "Basic Tişört")
		if err != nil || rec.Status != StatusNoProfile || len(rec.Missing) != 1 || rec.Missing[0] != "chest" {
			t.Fatalf("got %+v err=%v", rec, err)
		}
	})
	t.Run("profile without relevant measurement → incomplete", func(t *testing.T) {
		rec, err := newTestSvc(FitProfile{WaistMM: mm(800)}, nil).Recommend(ctx, 1, "Basic Tişört")
		if err != nil || rec.Status != StatusIncompleteProfile {
			t.Fatalf("got %+v err=%v", rec, err)
		}
	})
}

// rec is a tiny helper so each match case is a flat table row, keeping per-test
// cyclomatic complexity low.
func rec(t *testing.T, p FitProfile, title string) Recommendation {
	t.Helper()
	r, err := newTestSvc(p, nil).Recommend(context.Background(), 1, title)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	return r
}

func TestRecommend_MidRange(t *testing.T) {
	r := rec(t, FitProfile{ChestMM: mm(970)}, "Basic Tişört")
	if r.Status != StatusOK || r.Size != "M" || r.Signal != SignalTrueToSize {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_BoundaryRegular(t *testing.T) {
	// chest 1000 = M max / L min → between; regular picks the lower (M).
	r := rec(t, FitProfile{ChestMM: mm(1000), FitPref: FitRegular}, "Basic Tişört")
	if r.Signal != SignalBetween {
		t.Fatalf("signal: got %+v", r)
	}
	if r.BetweenLower != "M" || r.BetweenUpper != "L" || r.Size != "M" {
		t.Fatalf("between: got %+v", r)
	}
}

func TestRecommend_BoundaryLoose(t *testing.T) {
	r := rec(t, FitProfile{ChestMM: mm(1000), FitPref: FitLoose}, "Basic Tişört")
	if r.Signal != SignalBetween || r.Size != "L" {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_NearBoundaryBetween(t *testing.T) {
	// Contiguous charts: 992 is 8mm from L's min → within the 25mm between band.
	r := rec(t, FitProfile{ChestMM: mm(992)}, "Basic Tişört")
	if r.Signal != SignalBetween || r.Size != "M" {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_MultiMeasurementBottom(t *testing.T) {
	r := rec(t, FitProfile{WaistMM: mm(810), HipMM: mm(1010)}, "Slim Fit Pantolon")
	if r.Status != StatusOK || r.Size != "M" {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_SplitMeasurements(t *testing.T) {
	// waist→M, hip→L: least total distance wins deterministically (M or L).
	r := rec(t, FitProfile{WaistMM: mm(800), HipMM: mm(1080)}, "Slim Fit Pantolon")
	if r.Status != StatusOK || (r.Size != "M" && r.Size != "L") {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_PartialBottomProfile(t *testing.T) {
	r := rec(t, FitProfile{WaistMM: mm(810)}, "Slim Fit Pantolon")
	if r.Status != StatusOK || r.Size != "M" {
		t.Fatalf("status/size: got %+v", r)
	}
	if len(r.Missing) != 1 || r.Missing[0] != "hip" {
		t.Fatalf("missing: got %+v", r)
	}
}

func TestRecommend_BelowSmallest(t *testing.T) {
	r := rec(t, FitProfile{ChestMM: mm(700)}, "Basic Tişört")
	if r.Status != StatusOK || r.Size != "XS" || r.Signal != SignalTrueToSize {
		t.Fatalf("got %+v", r)
	}
}

func TestUpsertProfile_Validation(t *testing.T) {
	svc := newTestSvc(FitProfile{}, nil)
	ctx := context.Background()
	if err := svc.UpsertProfile(ctx, FitProfile{UserID: 1, ChestMM: mm(95)}); err == nil {
		t.Error("cm-typo chest (95mm) should be rejected")
	}
	if err := svc.UpsertProfile(ctx, FitProfile{UserID: 1, FitPref: "baggy"}); err == nil {
		t.Error("unknown fit_pref should be rejected")
	}
	if err := svc.UpsertProfile(ctx, FitProfile{UserID: 1, ChestMM: mm(950), FitPref: FitLoose}); err != nil {
		t.Errorf("valid profile rejected: %v", err)
	}
}
