//go:build contract

package api_test

// Contract tests: prove that hand-crafted JSON fixtures are internally
// consistent with the schemas declared in api/openapi.yaml.
//
// These tests do NOT call live handlers. They validate that the spec's
// schema definitions are self-consistent and that our fixture construction
// matches the spec. Live handler contract tests are added per-endpoint
// in subsequent sub-phases (Phase 4.4+).

import (
	"context"
	"encoding/json"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/getkin/kin-openapi/openapi3"
)

// specPath returns the absolute path to api/openapi.yaml relative to this file.
func specPath(t *testing.T) string {
	t.Helper()
	_, thisFile, _, _ := runtime.Caller(0)
	// internal/api/contract_test.go → ../../api/openapi.yaml
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "api", "openapi.yaml")
}

// loadDoc loads and validates the OpenAPI document.
func loadDoc(t *testing.T) *openapi3.T {
	t.Helper()
	loader := openapi3.NewLoader()
	doc, err := loader.LoadFromFile(specPath(t))
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	if err := doc.Validate(context.Background()); err != nil {
		t.Fatalf("spec validation: %v", err)
	}
	return doc
}

// validateFixture marshals v to JSON, unmarshals to interface{}, then validates
// against the named component schema in the doc.
func validateFixture(t *testing.T, doc *openapi3.T, schemaName string, v interface{}) {
	t.Helper()

	schemaRef, ok := doc.Components.Schemas[schemaName]
	if !ok {
		t.Fatalf("schema %q not found in components", schemaName)
	}

	// Round-trip through JSON so the validator sees the same representation
	// a client would receive.
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}

	var decoded interface{}
	if err := json.Unmarshal(b, &decoded); err != nil {
		t.Fatalf("unmarshal fixture: %v", err)
	}

	if err := schemaRef.Value.VisitJSON(decoded); err != nil {
		t.Errorf("fixture does not satisfy schema %q: %v\nJSON: %s", schemaName, err, b)
	}
}

// ── Test 1: GetProduct — Product schema ───────────────────────────────────────

func TestContract_GetProduct_ProductSchema(t *testing.T) {
	doc := loadDoc(t)

	color := "Siyah"
	size := "M"
	imageURL := "https://cdn.moproshop.com/products/tshirt-black.jpg"

	fixture := map[string]interface{}{
		"id":          int64(1),
		"seller_id":   int64(42),
		"seller_name": "Örnek Mağaza",
		"category_id": int64(5),
		"brand":       "TestBrand",
		"title":       "Siyah Tişört",
		"description": "Pamuk karışımlı rahat kesim tişört.",
		"status":      "active",
		"created_at":  time.Date(2026, 1, 15, 10, 0, 0, 0, time.UTC).Format(time.RFC3339),
		"cashback_preview": map[string]interface{}{
			"monthly_coin_minor": int64(625),
			"currency":           "TRY_COIN",
		},
		"variants": []interface{}{
			map[string]interface{}{
				"id":             int64(101),
				"sku":            "TSH-BLK-M-001",
				"price_minor":    int64(29900),
				"price_currency": "TRY",
				"stock":          15,
				"color":          &color,
				"size":           &size,
				"image_urls":     []interface{}{imageURL},
			},
		},
	}

	validateFixture(t, doc, "Product", fixture)
}

// ── Test 2: VerifyOtp — TokenPair schema ──────────────────────────────────────

func TestContract_VerifyOtp_TokenPairSchema(t *testing.T) {
	doc := loadDoc(t)

	fixture := map[string]interface{}{
		"access_token":       "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.stub",
		"refresh_token":      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.refresh-stub",
		"token_type":         "Bearer",
		"expires_in":         900,
		"refresh_expires_at": time.Date(2026, 2, 14, 10, 0, 0, 0, time.UTC).Format(time.RFC3339),
	}

	validateFixture(t, doc, "TokenPair", fixture)
}

// ── Test 3: ListCashbackPlans — cursor-paginated CashbackPlan list ───────────

func TestContract_ListCashbackPlans_ResponseSchema(t *testing.T) {
	doc := loadDoc(t)

	productImageURL := "https://cdn.moproshop.com/products/tshirt-black.jpg"

	// Validate CashbackPlan schema
	planFixture := map[string]interface{}{
		"id":                          int64(7),
		"order_id":                    int64(1001),
		"product_id":                  int64(1),
		"product_title":               "Siyah Tişört",
		"product_image_url":           &productImageURL,
		"monthly_amount_minor":        int64(625),
		"currency":                    "TRY_COIN",
		"reference_interest_rate_bps": 5000,
		"start_date":                  "2026-01-18",
		"status":                      "active",
		"created_at":                  time.Date(2026, 1, 15, 10, 0, 0, 0, time.UTC).Format(time.RFC3339),
	}
	validateFixture(t, doc, "CashbackPlan", planFixture)

	// Validate CursorPaginationMeta schema
	paginationFixture := map[string]interface{}{
		"next_cursor": "dGVzdC1jdXJzb3I=",
		"has_more":    false,
		"limit":       20,
	}
	validateFixture(t, doc, "CursorPaginationMeta", paginationFixture)
}
