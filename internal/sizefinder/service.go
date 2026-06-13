package sizefinder

import (
	"context"
	"errors"
	"fmt"
	"sort"
)

type service struct {
	repo Repository
}

// NewService builds the sizefinder service.
func NewService(repo Repository) Service {
	return &service{repo: repo}
}

// Sane human bounds (mm) — reject typos like cm-vs-mm slips early.
const (
	minMeasurementMM = 300    // 30 cm
	maxMeasurementMM = 2500   // 250 cm
	minHeightMM      = 800    // 80 cm
	maxHeightMM      = 2500   // 250 cm
	minWeightG       = 20000  // 20 kg
	maxWeightG       = 400000 // 400 kg
)

// betweenThresholdMM: two adjacent sizes within this total distance of each
// other count as "between sizes".
const betweenThresholdMM = 25

// edgeFraction: within this fraction of the recommended size's range edge,
// hint size_up (near top) / size_down (near bottom).
const edgeFraction = 0.15

func validRange(v *int, lo, hi int) bool {
	return v == nil || (*v >= lo && *v <= hi)
}

func (s *service) UpsertProfile(ctx context.Context, p FitProfile) error {
	switch p.FitPref {
	case "", FitRegular:
		p.FitPref = FitRegular
	case FitLoose, FitTight:
	default:
		return fmt.Errorf("%w: fit_pref %q", ErrInvalidMeasurement, p.FitPref)
	}
	switch p.Gender {
	case "", GenderUnspecified:
		p.Gender = GenderUnspecified
	case GenderFemale, GenderMale:
	default:
		return fmt.Errorf("%w: gender %q", ErrInvalidMeasurement, p.Gender)
	}
	if !validRange(p.ChestMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.WaistMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.HipMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.InseamMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.HeightMM, minHeightMM, maxHeightMM) ||
		!validRange(p.WeightG, minWeightG, maxWeightG) {
		return ErrInvalidMeasurement
	}
	return s.repo.UpsertProfile(ctx, p)
}

func (s *service) GetProfile(ctx context.Context, userID int64) (FitProfile, error) {
	return s.repo.GetProfile(ctx, userID)
}

// sizeScore is one candidate size's fit against the user's measurements.
type sizeScore struct {
	label string
	rank  int
	score int // Σ distance-to-range over present measurements (mm)
	// edge position of the binding measurement: -1 unknown, else per-mille (0..1000).
	edgePerMille int
}

func (s *service) Recommend(ctx context.Context, userID int64, productTitle string) (Recommendation, error) {
	// Honest about its limits: every response carries chart_approximate=true —
	// the charts are an EN 13402-3 standard baseline (not per-brand) and the
	// garment is classified from the title by keyword.
	rec := Recommendation{ChartApproximate: true}

	garment, ok := ClassifyTitle(productTitle)
	if !ok {
		rec.Status = StatusNoChart
		return rec, nil
	}
	rec.GarmentType = garment

	profile, err := s.repo.GetProfile(ctx, userID)
	if errors.Is(err, ErrProfileNotFound) {
		rec.Status = StatusNoProfile
		rec.Missing = relevantMeasurements(garment)
		return rec, nil
	}
	if err != nil {
		return Recommendation{}, err
	}

	chart, err := s.repo.ChartFor(ctx, garment, genderForChart(garment, profile.Gender))
	if err != nil {
		return Recommendation{}, err
	}
	if len(chart) == 0 {
		rec.Status = StatusNoChart
		return rec, nil
	}

	// Tier resolution: fill any missing relevant measurement with a basic
	// estimate from height/weight/gender. effective = real values + estimates;
	// `estimated` names the synthesized ones (→ BASIC confidence + warning).
	relevant := relevantMeasurements(garment)
	effective := profile
	var missing, estimated []string
	for _, m := range relevant {
		if measurementValue(profile, m) != nil {
			continue
		}
		if v, ok := estimateMeasurement(profile, m); ok {
			setMeasurement(&effective, m, v)
			estimated = append(estimated, m)
		} else {
			missing = append(missing, m)
		}
	}
	// NONE: no real measurement AND nothing estimable → prompt, never fabricate.
	present, _ := splitMeasurements(effective, relevant)
	if len(present) == 0 {
		rec.Status = StatusIncompleteProfile
		rec.Missing = relevant
		return rec, nil
	}

	scores := scoreSizes(chart, effective)
	rec.Status = StatusOK
	rec.Size = scores[0].label
	rec.Missing = missing
	rec.Estimated = estimated
	if len(estimated) > 0 {
		rec.Confidence = ConfidenceBasic
	} else {
		rec.Confidence = ConfidenceDetailed
	}
	applySignal(&rec, scores, profile.FitPref)
	return rec, nil
}

// splitMeasurements partitions the relevant measurements into those the profile
// provides and those it lacks.
func splitMeasurements(p FitProfile, relevant []string) (present, missing []string) {
	for _, m := range relevant {
		if measurementValue(p, m) != nil {
			present = append(present, m)
		} else {
			missing = append(missing, m)
		}
	}
	return present, missing
}

// scoreSizes groups the chart by size, scoring only the measurements the user
// provided, and returns the sizes ordered best-fit first (score asc, rank asc).
func scoreSizes(chart []ChartRow, profile FitProfile) []*sizeScore {
	bySize := map[string]*sizeScore{}
	for _, row := range chart {
		ss, ok := bySize[row.SizeLabel]
		if !ok {
			ss = &sizeScore{label: row.SizeLabel, rank: row.SortRank, edgePerMille: -1}
			bySize[row.SizeLabel] = ss
		}
		v := measurementValue(profile, row.Measurement)
		if v == nil {
			continue
		}
		switch {
		case *v < row.MinMM:
			ss.score += row.MinMM - *v
		case *v > row.MaxMM:
			ss.score += *v - row.MaxMM
		default:
			if span := row.MaxMM - row.MinMM; span > 0 {
				if pm := (*v - row.MinMM) * 1000 / span; pm > ss.edgePerMille {
					ss.edgePerMille = pm
				}
			}
		}
	}
	scores := make([]*sizeScore, 0, len(bySize))
	for _, ss := range bySize {
		scores = append(scores, ss)
	}
	sort.Slice(scores, func(i, j int) bool {
		if scores[i].score != scores[j].score {
			return scores[i].score < scores[j].score
		}
		return scores[i].rank < scores[j].rank
	})
	return scores
}

// applySignal sets the recommendation's size + signal: between-sizes (rank-
// adjacent runner-up within the threshold; fit_pref tiebreak) wins, else the
// edge hint for the best in-range size.
func applySignal(rec *Recommendation, scores []*sizeScore, fitPref string) {
	best := scores[0]
	if len(scores) > 1 {
		second := scores[1]
		rankAdjacent := second.rank == best.rank+1 || second.rank == best.rank-1
		if rankAdjacent && best.score+second.score <= betweenThresholdMM {
			lower, upper := best, second
			if upper.rank < lower.rank {
				lower, upper = upper, lower
			}
			rec.Signal = SignalBetween
			rec.BetweenLower = lower.label
			rec.BetweenUpper = upper.label
			// fit_pref tiebreak: loose → larger size, tight/regular → smaller.
			if fitPref == FitLoose {
				rec.Size = upper.label
			} else {
				rec.Size = lower.label
			}
			return
		}
	}
	switch {
	case best.score > 0:
		rec.Signal = SignalTrueToSize // nearest size (out of every range)
	case best.edgePerMille >= int(1000*(1-edgeFraction)):
		rec.Signal = SignalSizeUp
	case best.edgePerMille >= 0 && best.edgePerMille <= int(1000*edgeFraction):
		rec.Signal = SignalSizeDown
	default:
		rec.Signal = SignalTrueToSize
	}
}
