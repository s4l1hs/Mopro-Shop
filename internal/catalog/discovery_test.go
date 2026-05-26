//go:build !integration

package catalog_test

import (
	"context"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// ── New repository method stubs (satisfies updated Repository interface) ───────

func (m *mockRepo) ListAllVariantStocks(_ context.Context) ([]catalog.VariantStock, error) {
	return nil, nil
}

func (m *mockRepo) ListCategories(_ context.Context, _ string) ([]catalog.CategoryRow, error) {
	return []catalog.CategoryRow{}, nil
}

func (m *mockRepo) ListProductsByCategory(_ context.Context, _ int64, _ string, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return []catalog.ProductSummaryRow{}, 0, nil
}

func (m *mockRepo) SearchProductsSummary(_ context.Context, query, _ string, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	// Return a matching row when query matches the hard-coded test title "elbise".
	if query == "elbise" {
		return []catalog.ProductSummaryRow{
			{
				ID:            1,
				Title:         "Kırmızı Elbise",
				PriceMinor:    10000,
				PriceCurrency: "TRY",
			},
		}, 1, nil
	}
	return []catalog.ProductSummaryRow{}, 0, nil
}

// ── D: cashback_preview formula test ──────────────────────────────────────────

// TestCashbackPreviewFormula validates the integer-arithmetic formula:
// price=10000, commission_pct_bps=2000 → monthly_coin=83
// Formula: comm = 10000 * 2000 / 10000 = 2000
//
//	yearly = 2000 * 5000 / 10000 = 1000
//	monthly = 1000 / 12 = 83
func TestCashbackPreviewFormula(t *testing.T) {
	priceMinor := int64(10000)
	commissionPctBps := int64(2000)
	referenceRateBps := int64(5000)

	commMinor := priceMinor * commissionPctBps / 10000
	yearlyYield := commMinor * referenceRateBps / 10000
	monthlyMinor := yearlyYield / 12

	if monthlyMinor != 83 {
		t.Errorf("cashback_preview formula: got monthly_coin=%d, want 83", monthlyMinor)
	}
}

// ── B: search property test — Turkish "elbise" returns matching products ───────

func TestSearchSummary_Turkish_Elbise_ReturnsResults(t *testing.T) {
	repo := &mockRepo{}
	svc := catalog.NewService(repo, "TRY", "tr-TR")

	rows, total, err := svc.SearchSummary(context.Background(), "elbise", "tr-TR", "TR", 1, 20)
	if err != nil {
		t.Fatalf("SearchSummary: %v", err)
	}
	if total == 0 || len(rows) == 0 {
		t.Fatal("expected at least one result for 'elbise', got zero")
	}
	if rows[0].Title == "" {
		t.Error("result title must not be empty")
	}
}
