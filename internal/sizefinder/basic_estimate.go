package sizefinder

import "math"

// Basic-mode estimation (docs/internal/size-fit-basic.md): synthesize a missing
// garment-relevant measurement from height + weight + gender so users without
// detailed measurements still get a (clearly-approximate) size.
//
// APPROXIMATE BY DESIGN. The reference data is the §5 retail height/weight→size
// BAND tables (NOT EN 13402 — EN does not map weight to size). The bands overlap
// on purpose: two people at the same height/weight can sit a size apart, which is
// exactly why BASIC always renders with lower confidence + the inaccuracy
// warning. Method (dataset §5 recommended): a coarse (gender, height, weight) →
// alpha-size band lookup, then read that size's EN chart midpoint as the
// synthesized measurement so the result threads back through the same chart match
// (one source of truth; partial profiles handled for free). Fit-only: no BMI, no
// health/judgment.
//
// source: retail height/weight bands (approximate).

// sizeBand is one alpha size's height (cm) + weight (kg) window. Overlaps with
// its neighbours are intentional — do not "tidy" them.
type sizeBand struct {
	size           string
	rank           int // 1 = smallest (XS)
	hMinCm, hMaxCm float64
	wMinKg, wMaxKg float64
}

// basicBands — dataset §5a (women) / §5b (men). Overlaps preserved verbatim.
var basicBands = map[string][]sizeBand{
	GenderFemale: {
		{"XS", 1, 150, 165, 45, 54},
		{"S", 2, 155, 170, 53, 61},
		{"M", 3, 160, 175, 60, 70},
		{"L", 4, 163, 178, 69, 80},
		{"XL", 5, 165, 180, 79, 92},
		{"XXL", 6, 168, 182, 91, 105},
	},
	GenderMale: {
		{"XS", 1, 160, 172, 55, 63},
		{"S", 2, 163, 175, 62, 72},
		{"M", 3, 165, 178, 60, 72},
		{"L", 4, 172, 185, 70, 85},
		{"XL", 5, 178, 188, 80, 95},
		{"XXL", 6, 182, 193, 93, 110},
	},
}

// basicMidpointsMM maps a band rank (1-based) to the EN 13402-3 alpha chart
// midpoint (mm) for each measurement, per gender. Men have no hip column (EN
// sizes men's bottoms on waist) → male hip is intentionally absent (not
// estimable, degrades to a waist-only match).
var basicMidpointsMM = map[string]map[string][]int{
	GenderFemale: {
		"chest": {780, 860, 940, 1020, 1130, 1250},
		"waist": {620, 700, 780, 865, 970, 1090},
		"hip":   {860, 940, 1020, 1105, 1200, 1300},
	},
	GenderMale: {
		"chest": {820, 900, 980, 1060, 1140, 1235},
		"waist": {700, 780, 860, 940, 1020, 1115},
	},
}

// canEstimate reports whether the profile carries the basic inputs needed to
// synthesize measurements: height, weight, and a specified gender.
func canEstimate(p FitProfile) bool {
	return p.HeightMM != nil && p.WeightG != nil &&
		(p.Gender == GenderMale || p.Gender == GenderFemale)
}

// nearestRank votes the single band whose centre is closest to value (weight or
// height). Centres, not membership, because the bands overlap — membership would
// be ambiguous.
func nearestRank(bands []sizeBand, value float64, weight bool) int {
	best, bestDist := 0, math.MaxFloat64
	for i, b := range bands {
		center := (b.hMinCm + b.hMaxCm) / 2
		if weight {
			center = (b.wMinKg + b.wMaxKg) / 2
		}
		if d := math.Abs(value - center); d < bestDist {
			best, bestDist = i, d
		}
	}
	return best
}

// bandLookupSize maps (gender, height, weight) to an alpha band. Weight is the
// primary circumference signal; height only nudges UP by one size (the dataset's
// "on one-size disagreement return the larger" rule — under-tight is the more
// common returns driver). Larger disagreements defer to weight.
func bandLookupSize(gender string, heightCm, weightKg float64) (sizeBand, bool) {
	bands, ok := basicBands[gender]
	if !ok {
		return sizeBand{}, false
	}
	wIdx := nearestRank(bands, weightKg, true)
	hIdx := nearestRank(bands, heightCm, false)
	idx := wIdx
	if hIdx == wIdx+1 {
		idx = hIdx
	}
	return bands[idx], true
}

// estimateMeasurement returns the synthesized mm value for a measurement, or
// (0,false) if it can't be estimated (missing inputs, unknown measurement, or
// no chart column for the gender — e.g. male hip).
func estimateMeasurement(p FitProfile, measurement string) (int, bool) {
	if !canEstimate(p) {
		return 0, false
	}
	mids, ok := basicMidpointsMM[p.Gender][measurement]
	if !ok {
		return 0, false
	}
	band, ok := bandLookupSize(p.Gender,
		float64(*p.HeightMM)/10.0, float64(*p.WeightG)/1000.0)
	if !ok {
		return 0, false
	}
	idx := band.rank - 1
	if idx < 0 || idx >= len(mids) {
		return 0, false
	}
	return mids[idx], true
}
