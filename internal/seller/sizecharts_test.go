package seller

import (
	"errors"
	"testing"
)

// row is a terse SizeChartRow builder for the validation table.
func row(label string, rank int, m string, lo, hi int) SizeChartRow {
	return SizeChartRow{SizeLabel: label, SortRank: rank, Measurement: m, MinMM: lo, MaxMM: hi}
}

// a valid women's dress chart (chest+waist+hip, 2 sizes, monotonic, in bounds).
func validDress() SizeChart {
	return SizeChart{
		Name: "Marka Elbise", GarmentType: "dress", Gender: "female", SizeSystem: "alpha",
		Rows: []SizeChartRow{
			row("S", 1, "chest", 820, 900), row("M", 2, "chest", 900, 980),
			row("S", 1, "waist", 660, 740), row("M", 2, "waist", 740, 820),
			row("S", 1, "hip", 900, 980), row("M", 2, "hip", 980, 1060),
		},
	}
}

func TestValidateChart_OK(t *testing.T) {
	if err := validateChart(validDress()); err != nil {
		t.Fatalf("valid dress rejected: %v", err)
	}
	// a single-measurement top is also valid.
	top := SizeChart{Name: "Tişört", GarmentType: "top", Gender: "male", SizeSystem: "alpha",
		Rows: []SizeChartRow{row("M", 1, "chest", 940, 1020), row("L", 2, "chest", 1020, 1100)}}
	if err := validateChart(top); err != nil {
		t.Fatalf("valid top rejected: %v", err)
	}
}

func TestValidateChart_Rejections(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*SizeChart)
	}{
		{"bad garment", func(c *SizeChart) { c.GarmentType = "hat" }},
		{"bad gender", func(c *SizeChart) { c.Gender = "unspecified" }},
		{"bad size_system", func(c *SizeChart) { c.SizeSystem = "uk" }},
		{"empty name", func(c *SizeChart) { c.Name = "" }},
		{"missing measurement (drop hip)", func(c *SizeChart) {
			c.Rows = c.Rows[:4] // chest+waist only, dress needs hip
		}},
		{"extra measurement", func(c *SizeChart) {
			// inseam is not in dress's required set → len(byMeasure) != len(required).
			c.Rows = append(c.Rows, row("S", 1, "inseam", 700, 780), row("M", 2, "inseam", 780, 820))
		}},
		{"too few sizes", func(c *SizeChart) {
			c.Rows = []SizeChartRow{row("S", 1, "chest", 820, 900),
				row("S", 1, "waist", 660, 740), row("S", 1, "hip", 900, 980)}
		}},
		{"out of bounds (cm slip)", func(c *SizeChart) { c.Rows[0].MinMM = 82; c.Rows[0].MaxMM = 90 }},
		{"inverted range", func(c *SizeChart) { c.Rows[0].MinMM = 900; c.Rows[0].MaxMM = 820 }},
		{"non-monotonic", func(c *SizeChart) { c.Rows[1] = row("M", 2, "chest", 700, 780) }}, // M chest < S
		{"duplicate size", func(c *SizeChart) { c.Rows[1] = row("S", 2, "chest", 900, 980) }},
		{"ladder mismatch", func(c *SizeChart) { c.Rows[3] = row("L", 2, "waist", 740, 820) }}, // waist uses L not M
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := validDress()
			tc.mutate(&c)
			if err := validateChart(c); !errors.Is(err, ErrInvalidChart) {
				t.Fatalf("expected ErrInvalidChart, got %v", err)
			}
		})
	}
}
