//go:build integration

package catalog_test

// Integration tests for the P-032 seller price-update lifecycle + the P-030-PDP
// per-variant lowest_30d read. Reuses pfSetupCat/pfSeed (products under seller
// 900) + vphCount from the sibling integration files + the shared setupSchema
// (which mirrors #92's variants_price_history_trg).

import (
	"context"
	"errors"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

func pfVariantID(t *testing.T, ctx context.Context, productID int64) int64 {
	t.Helper()
	var id int64
	if err := integPool.QueryRow(ctx,
		`SELECT id FROM catalog_schema.variants WHERE product_id = $1`, productID).Scan(&id); err != nil {
		t.Fatalf("variant id: %v", err)
	}
	return id
}

func TestIntegration_UpdateVariantPrice(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)
	svc := catalog.NewService(repo, "TRY", "tr-TR")

	const owner = int64(900) // pfSeed inserts products under seller 900

	t.Run("owner update applies price + trigger logs history", func(t *testing.T) {
		p := pfSeed(t, ctx, "Bosch", "PU Happy", 50000, nil, 0, false, 5)
		vid := pfVariantID(t, ctx, p)
		orig := int64(60000)
		if err := svc.UpdateVariantPrice(ctx, owner, catalog.UpdateVariantPriceRequest{
			VariantID: vid, PriceMinor: 45000, OriginalPriceMinor: &orig,
		}); err != nil {
			t.Fatalf("UpdateVariantPrice: %v", err)
		}
		var price int64
		var op *int64
		if err := integPool.QueryRow(ctx,
			`SELECT price_minor, original_price_minor FROM catalog_schema.variants WHERE id = $1`,
			vid).Scan(&price, &op); err != nil {
			t.Fatalf("read variant: %v", err)
		}
		if price != 45000 || op == nil || *op != 60000 {
			t.Errorf("after update: price=%d original=%v, want 45000/60000", price, op)
		}
		if n := vphCount(t, ctx, p, "update"); n != 1 {
			t.Errorf("history 'update' rows: got %d, want 1", n)
		}
	})

	t.Run("non-owner cannot update (ErrVariantNotFound, price unchanged)", func(t *testing.T) {
		p := pfSeed(t, ctx, "Miele", "PU Owner", 50000, nil, 0, false, 5)
		vid := pfVariantID(t, ctx, p)
		err := svc.UpdateVariantPrice(ctx, owner+99, catalog.UpdateVariantPriceRequest{
			VariantID: vid, PriceMinor: 40000,
		})
		if !errors.Is(err, catalog.ErrVariantNotFound) {
			t.Errorf("non-owner: got %v, want ErrVariantNotFound", err)
		}
		var price int64
		integPool.QueryRow(ctx, `SELECT price_minor FROM catalog_schema.variants WHERE id = $1`, vid).Scan(&price)
		if price != 50000 {
			t.Errorf("price after non-owner attempt: got %d, want 50000 (unchanged)", price)
		}
	})

	t.Run("invalid price rejected (ErrInvalidPrice)", func(t *testing.T) {
		p := pfSeed(t, ctx, "AEG", "PU Invalid", 50000, nil, 0, false, 5)
		vid := pfVariantID(t, ctx, p)
		if err := svc.UpdateVariantPrice(ctx, owner, catalog.UpdateVariantPriceRequest{
			VariantID: vid, PriceMinor: 0,
		}); !errors.Is(err, catalog.ErrInvalidPrice) {
			t.Errorf("zero price: got %v, want ErrInvalidPrice", err)
		}
		bad := int64(40000) // original < price
		if err := svc.UpdateVariantPrice(ctx, owner, catalog.UpdateVariantPriceRequest{
			VariantID: vid, PriceMinor: 50000, OriginalPriceMinor: &bad,
		}); !errors.Is(err, catalog.ErrInvalidPrice) {
			t.Errorf("original<price: got %v, want ErrInvalidPrice", err)
		}
	})

	t.Run("GetByID variants carry per-variant lowest_30d (historical low)", func(t *testing.T) {
		p := pfSeed(t, ctx, "Grundig", "PU Lowest", 30000, nil, 0, false, 5)
		vid := pfVariantID(t, ctx, p)
		// Raise the price; the 30-day low stays at the pre-raise 30000.
		if err := svc.UpdateVariantPrice(ctx, owner, catalog.UpdateVariantPriceRequest{
			VariantID: vid, PriceMinor: 35000,
		}); err != nil {
			t.Fatalf("update: %v", err)
		}
		_, variants, _, err := svc.GetByID(ctx, p)
		if err != nil {
			t.Fatalf("GetByID: %v", err)
		}
		var found *catalog.Variant
		for i := range variants {
			if variants[i].ID == vid {
				found = &variants[i]
			}
		}
		if found == nil {
			t.Fatal("variant not returned by GetByID")
		}
		if found.PriceMinor != 35000 {
			t.Errorf("variant price: got %d, want 35000", found.PriceMinor)
		}
		if found.Lowest30dPriceMinor == nil || *found.Lowest30dPriceMinor != 30000 {
			t.Errorf("variant lowest_30d: got %v, want 30000 (pre-raise low)", found.Lowest30dPriceMinor)
		}
	})

	t.Run("GetByID variants carry original_price_minor (PDP strikethrough source)", func(t *testing.T) {
		get := func(productID, variantID int64) *catalog.Variant {
			_, variants, _, err := svc.GetByID(ctx, productID)
			if err != nil {
				t.Fatalf("GetByID(%d): %v", productID, err)
			}
			for i := range variants {
				if variants[i].ID == variantID {
					return &variants[i]
				}
			}
			t.Fatalf("variant %d not returned by GetByID", variantID)
			return nil
		}

		// Marked-down variant: original_price set above the live price → the PDP
		// strikethrough source flows through loadVariants.
		disc := pfSeed(t, ctx, "Vestel", "PU Strike", 60000, nil, 0, false, 5)
		dvid := pfVariantID(t, ctx, disc)
		orig := int64(60000)
		if err := svc.UpdateVariantPrice(ctx, owner, catalog.UpdateVariantPriceRequest{
			VariantID: dvid, PriceMinor: 45000, OriginalPriceMinor: &orig,
		}); err != nil {
			t.Fatalf("update: %v", err)
		}
		if d := get(disc, dvid); d.OriginalPriceMinor == nil || *d.OriginalPriceMinor != 60000 {
			t.Errorf("discounted variant original_price: got %v, want 60000", d.OriginalPriceMinor)
		}

		// Never-discounted variant: original_price_minor stays nil (omitempty).
		plain := pfSeed(t, ctx, "Vestel", "PU Plain", 30000, nil, 0, false, 5)
		pvid := pfVariantID(t, ctx, plain)
		if pl := get(plain, pvid); pl.OriginalPriceMinor != nil {
			t.Errorf("never-discounted variant original_price: got %d, want nil", *pl.OriginalPriceMinor)
		}
	})
}
