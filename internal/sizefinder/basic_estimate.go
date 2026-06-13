package sizefinder

// Basic-mode estimation (docs/internal/size-fit-basic.md): synthesize a missing
// garment-relevant measurement from height + weight + gender so users without
// detailed measurements still get a (clearly-approximate) size.
//
// APPROXIMATE BY DESIGN — illustrative gender-specific linear models, NOT
// curated anthropometric tables (curation follows alongside the charts). Circumference
// in mm scales mainly with weight (kg), plus a small height term and a gender
// base. Fit-only: no BMI, no health/judgment.

// estimateCoeffs holds the per-gender linear coefficients for one measurement:
// mm = base + perKg*kg + perCmAbove170*(heightCm-170).
type estimateCoeffs struct {
	base, perKg, perCm float64
}

// Coefficients chosen so average inputs land mid-chart (e.g. male 80kg/180cm ≈ L,
// female 60kg/165cm ≈ S/M). Deliberately rough — the BASIC warning says so.
var estimateTable = map[string]map[string]estimateCoeffs{
	"chest": {
		GenderMale:   {base: 720, perKg: 4.0, perCm: 2.0},
		GenderFemale: {base: 660, perKg: 4.0, perCm: 2.0},
	},
	"waist": {
		GenderMale:   {base: 500, perKg: 4.0, perCm: 1.5},
		GenderFemale: {base: 480, perKg: 4.0, perCm: 1.5},
	},
	"hip": {
		GenderMale:   {base: 700, perKg: 3.5, perCm: 1.5},
		GenderFemale: {base: 720, perKg: 3.5, perCm: 2.0},
	},
}

// canEstimate reports whether the profile carries the basic inputs needed to
// synthesize measurements: height, weight, and a specified gender.
func canEstimate(p FitProfile) bool {
	return p.HeightMM != nil && p.WeightG != nil &&
		(p.Gender == GenderMale || p.Gender == GenderFemale)
}

// estimateMeasurement returns the synthesized mm value for a measurement, or
// (0,false) if it can't be estimated (missing inputs or unknown measurement).
func estimateMeasurement(p FitProfile, measurement string) (int, bool) {
	if !canEstimate(p) {
		return 0, false
	}
	byGender, ok := estimateTable[measurement]
	if !ok {
		return 0, false
	}
	c, ok := byGender[p.Gender]
	if !ok {
		return 0, false
	}
	kg := float64(*p.WeightG) / 1000.0
	heightCm := float64(*p.HeightMM) / 10.0
	mm := c.base + c.perKg*kg + c.perCm*(heightCm-170.0)
	if mm < 1 {
		mm = 1
	}
	return int(mm + 0.5), true
}
