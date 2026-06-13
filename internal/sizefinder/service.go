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
	minMeasurementMM = 300  // 30 cm
	maxMeasurementMM = 2500 // 250 cm
	minHeightMM      = 800  // 80 cm
	maxHeightMM      = 2500 // 250 cm
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
	if !validRange(p.ChestMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.WaistMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.HipMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.InseamMM, minMeasurementMM, maxMeasurementMM) ||
		!validRange(p.HeightMM, minHeightMM, maxHeightMM) {
		return ErrInvalidMeasurement
	}
	return s.repo.UpsertProfile(ctx, p)
}

func (s *service) GetProfile(ctx context.Context, userID int64) (FitProfile, error) {
	return s.repo.GetProfile(ctx, userID)
}

func (s *service) Recommend(ctx context.Context, userID int64, productTitle string) (Recommendation, error) {
	// Phase 1 is honest about its limits: every response carries
	// chart_approximate=true (representative seed charts + keyword classifier).
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

	chart, err := s.repo.ChartFor(ctx, garment)
	if err != nil {
		return Recommendation{}, err
	}
	if len(chart) == 0 {
		rec.Status = StatusNoChart
		return rec, nil
	}

	relevant := relevantMeasurements(garment)
	var present, missing []string
	for _, m := range relevant {
		if measurementValue(profile, m) != nil {
			present = append(present, m)
		} else {
			missing = append(missing, m)
		}
	}
	if len(present) == 0 {
		rec.Status = StatusIncompleteProfile
		rec.Missing = missing
		return rec, nil
	}

	// Group the chart by size, scoring only the measurements the user provided.
	type sizeScore struct {
		label string
		rank  int
		score int // Σ distance-to-range over present measurements (mm)
		// edge position of the binding (largest-range-share) measurement:
		// -1 unknown, else 0..1000 (per-mille within the range).
		edgePerMille int
	}
	bySize := map[string]*sizeScore{}
	for _, row := range chart {
		ss, okSize := bySize[row.SizeLabel]
		if !okSize {
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
			// In range: track where within the range (for edge hints).
			span := row.MaxMM - row.MinMM
			if span > 0 {
				pm := (*v - row.MinMM) * 1000 / span
				if pm > ss.edgePerMille {
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

	best := scores[0]
	rec.Status = StatusOK
	rec.Size = best.label
	rec.Missing = missing

	// Between-sizes: the runner-up is rank-adjacent and both fit nearly as well.
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
			// fit_pref tiebreak: loose → the larger size, tight/regular → smaller.
			if profile.FitPref == FitLoose {
				rec.Size = upper.label
			} else {
				rec.Size = lower.label
			}
			return rec, nil
		}
	}

	// Edge hints: near the top of the range → consider sizing up; near the
	// bottom → down. Only meaningful when the best size actually fit (score 0).
	switch {
	case best.score > 0:
		rec.Signal = SignalTrueToSize // nearest size (out of every range)
	case best.edgePerMille >= 0 && best.edgePerMille >= int(1000*(1-edgeFraction)):
		rec.Signal = SignalSizeUp
	case best.edgePerMille >= 0 && best.edgePerMille <= int(1000*edgeFraction):
		rec.Signal = SignalSizeDown
	default:
		rec.Signal = SignalTrueToSize
	}
	return rec, nil
}
