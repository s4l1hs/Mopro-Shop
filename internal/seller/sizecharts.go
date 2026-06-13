package seller

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"
)

// Seller-entered size charts (docs/internal/seller-size-charts.md). Sellers author
// per-garment charts that the match service prefers over the EN 13402-3 standard
// baseline. Product data — plaintext integer millimetres (NOT the §6 EncryptPII
// path that fit *profiles* use). Owned by seller_schema.

var (
	// ErrInvalidChart is returned when a submitted chart fails validation (→ 422).
	ErrInvalidChart = errors.New("seller: invalid size chart")
	// ErrChartNotFound is returned when a chart is absent or not owned (→ 404, no leak).
	ErrChartNotFound = errors.New("seller: size chart not found")
)

// Chart measurement / enum bounds (mirror sizefinder's sane mm bounds — reject
// cm/mm slips). Kept local: seller (core-svc) does not import sizefinder (jobs-svc).
const (
	chartMinMM = 300  // 30 cm
	chartMaxMM = 2500 // 250 cm
)

// SizeChartRow is one (size, measurement) range of a seller chart, mirroring the
// ref_schema.size_charts row shape so the match treats them identically.
type SizeChartRow struct {
	SizeLabel   string `json:"size_label"`
	SortRank    int    `json:"sort_rank"`
	Measurement string `json:"measurement"` // chest | waist | hip
	MinMM       int    `json:"min_mm"`
	MaxMM       int    `json:"max_mm"`
}

// SizeChart is a seller-authored chart header + its rows.
type SizeChart struct {
	ID          int64          `json:"id"`
	SellerID    int64          `json:"seller_id"`
	Name        string         `json:"name"`
	GarmentType string         `json:"garment_type"` // top|bottom|dress|skirt|outerwear
	Gender      string         `json:"gender"`       // female|male
	SizeSystem  string         `json:"size_system"`  // alpha|eu
	Source      string         `json:"source"`       // always "seller"
	Rows        []SizeChartRow `json:"rows"`
	CreatedAt   time.Time      `json:"created_at,omitempty"`
	UpdatedAt   time.Time      `json:"updated_at,omitempty"`
}

// chartRequiredMeasurements is the EN 13402-2 garment→dimension map (local copy of
// sizefinder.relevantMeasurements — the boundary forbids importing it). A seller
// chart MUST carry exactly these measurements for its garment type.
func chartRequiredMeasurements(garment string) []string {
	switch garment {
	case "top", "outerwear":
		return []string{"chest"}
	case "bottom", "skirt":
		return []string{"waist", "hip"}
	case "dress":
		return []string{"chest", "waist", "hip"}
	}
	return nil
}

func validGender(g string) bool     { return g == "female" || g == "male" }
func validSizeSystem(s string) bool { return s == "alpha" || s == "eu" }

// validateChart hard-rejects a malformed seller chart (a non-monotonic or
// incomplete chart is a data error, not a warning).
func validateChart(c SizeChart) error {
	if c.Name == "" {
		return fmt.Errorf("%w: name required", ErrInvalidChart)
	}
	required := chartRequiredMeasurements(c.GarmentType)
	if required == nil {
		return fmt.Errorf("%w: garment_type %q", ErrInvalidChart, c.GarmentType)
	}
	if !validGender(c.Gender) {
		return fmt.Errorf("%w: gender %q", ErrInvalidChart, c.Gender)
	}
	if !validSizeSystem(c.SizeSystem) {
		return fmt.Errorf("%w: size_system %q", ErrInvalidChart, c.SizeSystem)
	}

	byMeasure := map[string][]SizeChartRow{}
	for _, r := range c.Rows {
		if r.MinMM < chartMinMM || r.MaxMM <= r.MinMM || r.MaxMM > chartMaxMM {
			return fmt.Errorf("%w: row %s/%s out of bounds (%d–%d mm)",
				ErrInvalidChart, r.SizeLabel, r.Measurement, r.MinMM, r.MaxMM)
		}
		byMeasure[r.Measurement] = append(byMeasure[r.Measurement], r)
	}
	// Measurements must be EXACTLY the garment's required set (no missing, no extra).
	if len(byMeasure) != len(required) {
		return fmt.Errorf("%w: %s needs measurements %v", ErrInvalidChart, c.GarmentType, required)
	}
	var labelSet0 []string
	for i, m := range required {
		rows, ok := byMeasure[m]
		if !ok {
			return fmt.Errorf("%w: missing measurement %q", ErrInvalidChart, m)
		}
		if len(rows) < 2 {
			return fmt.Errorf("%w: measurement %q needs ≥2 sizes", ErrInvalidChart, m)
		}
		sort.Slice(rows, func(a, b int) bool { return rows[a].SortRank < rows[b].SortRank })
		// unique labels + strictly increasing rank + monotonic non-decreasing ranges.
		seen := map[string]bool{}
		labels := make([]string, 0, len(rows))
		for j, r := range rows {
			if seen[r.SizeLabel] {
				return fmt.Errorf("%w: duplicate size %q for %q", ErrInvalidChart, r.SizeLabel, m)
			}
			seen[r.SizeLabel] = true
			labels = append(labels, r.SizeLabel)
			if j > 0 {
				prev := rows[j-1]
				if r.SortRank <= prev.SortRank {
					return fmt.Errorf("%w: sort_rank not increasing for %q", ErrInvalidChart, m)
				}
				if r.MinMM < prev.MinMM || r.MaxMM < prev.MaxMM {
					return fmt.Errorf("%w: %q not monotonic at %s (must grow with size)",
						ErrInvalidChart, m, r.SizeLabel)
				}
			}
		}
		// every measurement must share the same size ladder.
		if i == 0 {
			labelSet0 = labels
		} else if !sameLabels(labelSet0, labels) {
			return fmt.Errorf("%w: size ladder differs across measurements", ErrInvalidChart)
		}
	}
	return nil
}

func sameLabels(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	set := map[string]bool{}
	for _, x := range a {
		set[x] = true
	}
	for _, y := range b {
		if !set[y] {
			return false
		}
	}
	return true
}

// ── Service methods ─────────────────────────────────────────────────────────

func (s *service) CreateSizeChart(ctx context.Context, sellerID int64, c SizeChart) (int64, error) {
	c.SellerID = sellerID
	c.Source = "seller"
	if err := validateChart(c); err != nil {
		return 0, err
	}
	return s.repo.InsertSizeChart(ctx, c)
}

func (s *service) UpdateSizeChart(ctx context.Context, sellerID, chartID int64, c SizeChart) error {
	c.SellerID = sellerID
	c.ID = chartID
	c.Source = "seller"
	if err := validateChart(c); err != nil {
		return err
	}
	return s.repo.ReplaceSizeChart(ctx, sellerID, chartID, c)
}

func (s *service) ListSizeCharts(ctx context.Context, sellerID int64) ([]SizeChart, error) {
	return s.repo.ListSizeChartsBySeller(ctx, sellerID)
}

// AttachProductChart links a product to one of the seller's charts. Chart
// ownership is verified here; PRODUCT ownership is the caller's responsibility
// (catalog-side, §5 — seller cannot read catalog_schema).
func (s *service) AttachProductChart(ctx context.Context, sellerID, productID, chartID int64) error {
	owned, err := s.repo.ChartOwnedBy(ctx, sellerID, chartID)
	if err != nil {
		return err
	}
	if !owned {
		return ErrChartNotFound
	}
	return s.repo.AttachProductChart(ctx, productID, chartID, sellerID)
}

func (s *service) DetachProductChart(ctx context.Context, sellerID, productID int64) error {
	return s.repo.DetachProductChart(ctx, productID, sellerID)
}

// SizeChartForProduct resolves the chart attached to a product (for the match;
// no seller filter — reads are public to the recommend path). (false) when none.
func (s *service) SizeChartForProduct(ctx context.Context, productID int64) (SizeChart, bool, error) {
	return s.repo.SizeChartForProduct(ctx, productID)
}
