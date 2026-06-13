package sizefinder

import "testing"

// EN 13402-3 curation lock-in tests: known bodies must map to the EN-expected
// alpha size on the curated charts. If these flip, the seed drifted from EN.

// Woman bust 92 / waist 78 / hip 100 → M (EN women dress: bust 90–98, waist
// 74–82, hip 98–106 all land in M). All measurements real → DETAILED, no warning.
func TestEN_WomanDressMapsToM(t *testing.T) {
	r := rec(t, FitProfile{
		ChestMM: mm(920), WaistMM: mm(780), HipMM: mm(1000), Gender: GenderFemale,
	}, "Yazlık Çiçekli Elbise")
	if r.Status != StatusOK || r.Size != "M" || r.Confidence != ConfidenceDetailed {
		t.Fatalf("woman bust92/waist78/hip100 → M (detailed): got %+v", r)
	}
	if len(r.Estimated) != 0 {
		t.Fatalf("all-real profile must not estimate: got %+v", r)
	}
}

// Man chest in the EN men's L band (102–110) → L on the male chart, not the
// women's bust bands. Uses mid-band 106 cm: 104 cm sits only 2 cm above the M/L
// seam (M = 94–102), inside the 25 mm "between" window, so it honestly flags
// between-sizes — mid-band locks the L band → L mapping cleanly.
func TestEN_ManTopMapsToL(t *testing.T) {
	r := rec(t, FitProfile{ChestMM: mm(1060), Gender: GenderMale}, "Nike Dri-FIT Tişört")
	if r.Status != StatusOK || r.Size != "L" {
		t.Fatalf("man chest106 → L: got %+v", r)
	}
}

// BASIC woman 168 cm / 75 kg → L (dataset §5a: weight 75 → L band), AND the
// response is flagged BASIC with an estimated measurement so the UI shows the
// approximate warning.
func TestEN_BasicWomanMapsToLWarned(t *testing.T) {
	r := rb(t, FitProfile{
		HeightMM: gi(1680), WeightG: gi(75000), Gender: GenderFemale,
	}, "Basic Tişört")
	if r.Status != StatusOK || r.Size != "L" {
		t.Fatalf("basic woman 168/75 → L: got %+v", r)
	}
	if r.Confidence != ConfidenceBasic || len(r.Estimated) == 0 {
		t.Fatalf("basic estimate must carry the warning flags: got %+v", r)
	}
}
