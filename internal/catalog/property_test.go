//go:build integration

package catalog_test

// Property test: for any N variant inserts on a product, GetByID returns exactly
// those N variants in deterministic (id-ascending) order.

import (
	"context"
	"fmt"
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/internal/catalog"
)

func TestProperty_GetByIDVariantOrderDeterministic(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 30
	properties := gopter.NewProperties(params)

	ctx := context.Background()

	properties.Property(
		"GetByID returns exactly N variants in id-asc order after N AddVariant calls",
		prop.ForAll(
			func(n uint8) bool {
				// n in [1,10] to keep tests fast
				count := int(n%10) + 1

				repo := catalog.NewRepository(integPool)
				svc := catalog.NewService(repo, "TRY", "tr-TR")

				p, err := svc.CreateProduct(ctx, catalog.CreateProductRequest{
					SellerID: 999, CategoryID: 30, Brand: "PropTest",
				})
				if err != nil {
					t.Logf("CreateProduct error: %v", err)
					return false
				}

				var insertedIDs []int64
				for i := 0; i < count; i++ {
					v, err := svc.AddVariant(ctx, p.ID, catalog.AddVariantRequest{
						SKU:        fmt.Sprintf("PROP-SKU-%d-%d", p.ID, i),
						PriceMinor: int64((i + 1) * 1000),
					})
					if err != nil {
						t.Logf("AddVariant[%d] error: %v", i, err)
						return false
					}
					insertedIDs = append(insertedIDs, v.ID)
				}

				_, variants, _, err := svc.GetByID(ctx, p.ID)
				if err != nil {
					t.Logf("GetByID error: %v", err)
					return false
				}

				if len(variants) != count {
					t.Logf("expected %d variants, got %d", count, len(variants))
					return false
				}

				// IDs must be ascending (ORDER BY id ASC in repository).
				for i := 1; i < len(variants); i++ {
					if variants[i].ID <= variants[i-1].ID {
						t.Logf("variants not in id-asc order at index %d", i)
						return false
					}
				}

				// IDs must match inserted IDs.
				for i, v := range variants {
					if v.ID != insertedIDs[i] {
						t.Logf("variant[%d] ID mismatch: want %d got %d", i, insertedIDs[i], v.ID)
						return false
					}
				}

				return true
			},
			gen.UInt8(),
		),
	)
	properties.TestingRun(t)
}
