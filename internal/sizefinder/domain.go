package sizefinder

import "time"

// Phase-1 size-fit domain (docs/internal/size-fit.md). Measurements are integer
// MILLIMETRES end-to-end (no floats — the money-type discipline applied to
// lengths); they are stored only as AES-GCM ciphertext (§6).

// GarmentType classifies what a chart fits. Charts key on garment type, NOT
// category — the taxonomy is too coarse (a category holds tops and bottoms).
type GarmentType string

const (
	GarmentTop       GarmentType = "top"
	GarmentBottom    GarmentType = "bottom"
	GarmentDress     GarmentType = "dress"
	GarmentSkirt     GarmentType = "skirt"
	GarmentOuterwear GarmentType = "outerwear"
)

// Fit preferences (tiebreak for between-sizes).
const (
	FitRegular = "regular"
	FitLoose   = "loose"
	FitTight   = "tight"
)

// Gender categories (basic-estimation input; not a measurement).
const (
	GenderFemale      = "female"
	GenderMale        = "male"
	GenderUnspecified = "unspecified"
)

// Confidence of a recommendation.
const (
	ConfidenceDetailed = "detailed" // every relevant measurement was real
	ConfidenceBasic    = "basic"    // >=1 measurement was estimated
)

// FitProfile is a user's measurements in mm. Nil pointer = not provided.
type FitProfile struct {
	UserID    int64     `json:"user_id"`
	ChestMM   *int      `json:"chest_mm,omitempty"`
	WaistMM   *int      `json:"waist_mm,omitempty"`
	HipMM     *int      `json:"hip_mm,omitempty"`
	InseamMM  *int      `json:"inseam_mm,omitempty"`
	HeightMM  *int      `json:"height_mm,omitempty"`
	WeightG   *int      `json:"weight_g,omitempty"` // grams (encrypted at rest)
	Gender    string    `json:"gender"`             // female | male | unspecified
	FitPref   string    `json:"fit_pref"`
	UpdatedAt time.Time `json:"updated_at"`
}

// ChartRow is one (size, measurement) range of a garment-type chart.
type ChartRow struct {
	GarmentType GarmentType
	SizeLabel   string
	SortRank    int
	Measurement string // chest | waist | hip
	MinMM       int
	MaxMM       int
}

// Recommendation statuses.
const (
	StatusOK                = "ok"
	StatusNoProfile         = "no_profile"
	StatusIncompleteProfile = "incomplete_profile"
	StatusNoChart           = "no_chart"
)

// Recommendation signals.
const (
	SignalTrueToSize = "true_to_size"
	SignalBetween    = "between"
	SignalSizeUp     = "size_up"
	SignalSizeDown   = "size_down"
)

// Recommendation is the match output. ChartApproximate is ALWAYS true: the
// charts are an EN 13402-3 STANDARD reference baseline, not per-brand truth —
// seller-entered charts will override it per product later.
type Recommendation struct {
	Status       string      `json:"status"`
	GarmentType  GarmentType `json:"garment_type,omitempty"`
	Size         string      `json:"size,omitempty"`
	Signal       string      `json:"signal,omitempty"`
	BetweenLower string      `json:"between_lower,omitempty"`
	BetweenUpper string      `json:"between_upper,omitempty"`
	Missing      []string    `json:"missing,omitempty"`
	// Confidence: detailed (all real) | basic (>=1 estimated). Empty for
	// non-ok statuses.
	Confidence string `json:"confidence,omitempty"`
	// Estimated names the relevant measurements that were synthesized from
	// height/weight/gender (drives the "approximate" warning).
	Estimated        []string `json:"estimated,omitempty"`
	ChartApproximate bool     `json:"chart_approximate"`
}

// relevantMeasurements per garment type. Bottoms/skirts use waist+hip; inseam
// is collected on the profile for future length recs but no phase-1 chart
// carries it.
func relevantMeasurements(g GarmentType) []string {
	switch g {
	case GarmentTop, GarmentOuterwear:
		return []string{"chest"}
	case GarmentBottom, GarmentSkirt:
		return []string{"waist", "hip"}
	case GarmentDress:
		return []string{"chest", "waist", "hip"}
	}
	return nil
}

// genderForChart resolves which gendered chart to match against (EN 13402-3
// separates women's bust bands from men's chest bands). Women-only garments
// (dress, skirt) always use the female chart; otherwise male iff the profile
// says male, else female — the default for female AND unspecified.
func genderForChart(g GarmentType, profileGender string) string {
	switch g {
	case GarmentDress, GarmentSkirt:
		return GenderFemale
	}
	if profileGender == GenderMale {
		return GenderMale
	}
	return GenderFemale
}

// measurementValue resolves a named measurement from the profile (nil = absent).
func measurementValue(p FitProfile, name string) *int {
	switch name {
	case "chest":
		return p.ChestMM
	case "waist":
		return p.WaistMM
	case "hip":
		return p.HipMM
	}
	return nil
}

// setMeasurement writes a named measurement onto a profile copy (used to fold
// basic estimates into an effective profile before matching).
func setMeasurement(p *FitProfile, name string, mm int) {
	switch name {
	case "chest":
		p.ChestMM = &mm
	case "waist":
		p.WaistMM = &mm
	case "hip":
		p.HipMM = &mm
	}
}
