package sizefinder

import (
	"context"
	"testing"
)

// chartKey is (garment, resolved-gender) — the fake mirrors the gendered
// ref_schema.size_charts the live repo queries (alpha system only).
type chartKey struct {
	g      GarmentType
	gender string
}

type fakeRepo struct {
	profile    FitProfile
	profileErr error
	charts     map[chartKey][]ChartRow
}

func (f *fakeRepo) UpsertProfile(context.Context, FitProfile) error { return nil }
func (f *fakeRepo) GetProfile(context.Context, int64) (FitProfile, error) {
	return f.profile, f.profileErr
}
func (f *fakeRepo) ChartFor(_ context.Context, g GarmentType, gender string) ([]ChartRow, error) {
	return f.charts[chartKey{g, gender}], nil
}

func mm(v int) *int { return &v }

// chartRows builds an XS…XXL ladder for one measurement from {rank,min,max} mm
// triples (EN 13402-3 alpha bands).
func chartRows(g GarmentType, measurement string, ranges [][3]int) []ChartRow {
	labels := []string{"XS", "S", "M", "L", "XL", "XXL"}
	out := make([]ChartRow, 0, len(ranges))
	for i, r := range ranges {
		out = append(out, ChartRow{
			GarmentType: g, SizeLabel: labels[i], SortRank: r[0],
			Measurement: measurement, MinMM: r[1], MaxMM: r[2],
		})
	}
	return out
}

// EN 13402-3 alpha bands (mm) used across the unit tests.
var (
	womenBust  = [][3]int{{1, 740, 820}, {2, 820, 900}, {3, 900, 980}, {4, 980, 1060}, {5, 1070, 1190}, {6, 1190, 1310}}
	womenWaist = [][3]int{{1, 580, 660}, {2, 660, 740}, {3, 740, 820}, {4, 820, 910}, {5, 910, 1030}, {6, 1030, 1150}}
	womenHip   = [][3]int{{1, 820, 900}, {2, 900, 980}, {3, 980, 1060}, {4, 1060, 1150}, {5, 1150, 1250}, {6, 1250, 1350}}
	menChest   = [][3]int{{1, 780, 860}, {2, 860, 940}, {3, 940, 1020}, {4, 1020, 1100}, {5, 1100, 1180}, {6, 1180, 1290}}
)

func concat(rows ...[]ChartRow) []ChartRow {
	var out []ChartRow
	for _, r := range rows {
		out = append(out, r...)
	}
	return out
}

// newTestSvc wires a fake with the gendered EN charts the tests exercise:
// women top/bottom/dress + men top.
func newTestSvc(p FitProfile, perr error) Service {
	return NewService(&fakeRepo{profile: p, profileErr: perr,
		charts: map[chartKey][]ChartRow{
			{GarmentTop, GenderFemale}:    chartRows(GarmentTop, "chest", womenBust),
			{GarmentBottom, GenderFemale}: concat(chartRows(GarmentBottom, "waist", womenWaist), chartRows(GarmentBottom, "hip", womenHip)),
			{GarmentDress, GenderFemale}: concat(
				chartRows(GarmentDress, "chest", womenBust),
				chartRows(GarmentDress, "waist", womenWaist),
				chartRows(GarmentDress, "hip", womenHip)),
			{GarmentTop, GenderMale}: chartRows(GarmentTop, "chest", menChest),
		}})
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
	// women bust M = 900–980; 940 is mid-band → true to size.
	r := rec(t, FitProfile{ChestMM: mm(940)}, "Basic Tişört")
	if r.Status != StatusOK || r.Size != "M" || r.Signal != SignalTrueToSize {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_BoundaryRegular(t *testing.T) {
	// chest 980 = M max / L min → between; regular picks the lower (M).
	r := rec(t, FitProfile{ChestMM: mm(980), FitPref: FitRegular}, "Basic Tişört")
	if r.Signal != SignalBetween {
		t.Fatalf("signal: got %+v", r)
	}
	if r.BetweenLower != "M" || r.BetweenUpper != "L" || r.Size != "M" {
		t.Fatalf("between: got %+v", r)
	}
}

func TestRecommend_BoundaryLoose(t *testing.T) {
	r := rec(t, FitProfile{ChestMM: mm(980), FitPref: FitLoose}, "Basic Tişört")
	if r.Signal != SignalBetween || r.Size != "L" {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_NearBoundaryBetween(t *testing.T) {
	// 972 is 8mm below L's min (980) → within the 25mm between band; regular → M.
	r := rec(t, FitProfile{ChestMM: mm(972)}, "Basic Tişört")
	if r.Signal != SignalBetween || r.Size != "M" {
		t.Fatalf("got %+v", r)
	}
}

func TestRecommend_MultiMeasurementBottom(t *testing.T) {
	// women bottom M: waist 740–820, hip 980–1060.
	r := rec(t, FitProfile{WaistMM: mm(800), HipMM: mm(1010)}, "Slim Fit Pantolon")
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
	r := rec(t, FitProfile{WaistMM: mm(800)}, "Slim Fit Pantolon")
	if r.Status != StatusOK || r.Size != "M" {
		t.Fatalf("status/size: got %+v", r)
	}
	if len(r.Missing) != 1 || r.Missing[0] != "hip" {
		t.Fatalf("missing: got %+v", r)
	}
}

func TestRecommend_BelowSmallest(t *testing.T) {
	// women bust XS starts at 740; 700 falls below → nearest is XS, true to size.
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
