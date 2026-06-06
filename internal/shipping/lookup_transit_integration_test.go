//go:build integration

package shipping_test

import (
	"context"
	"os"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/shipping"
)

// Live-Postgres coverage for the P-034 pre-purchase ETA reference lookups
// (shipping.Repository.LookupTransit / LookupTransitDefault), gated on
// SHIPPING_TEST_DSN. The schema + TR seed come from the REAL migration file
// (migrations/ecom/0085_shipping_zones.up.sql), so this also verifies the seed
// itself — the value PR #97 flagged ("LookupTransit/LookupTransitDefault against
// real Postgres and the 0085 seed run at make verify time"). EstimateETA's
// higher-level logic is unit-tested via a stub repo in service_test.go; this
// exercises only the SQL joins + the seeded values.

const shippingMigration = "../../migrations/ecom/0085_shipping_zones.up.sql"

var (
	shipOnce sync.Once
	shipPool *pgxpool.Pool
	shipErr  error
)

// shippingRepo returns a Repository backed by a freshly-seeded ref_schema, or
// skips when SHIPPING_TEST_DSN is unset (so a bare `-tags=integration` run with
// no database is a skip, not a hard failure — unlike a TestMain that os.Exit()s).
func shippingRepo(t *testing.T) shipping.Repository {
	t.Helper()
	dsn := os.Getenv("SHIPPING_TEST_DSN")
	if dsn == "" {
		t.Skip("SHIPPING_TEST_DSN not set; skipping shipping ref_schema integration test")
	}
	shipOnce.Do(func() { shipPool, shipErr = setupShippingSeed(dsn) })
	if shipErr != nil {
		t.Fatalf("shipping seed setup: %v", shipErr)
	}
	return shipping.NewRepository(shipPool)
}

// setupShippingSeed opens a simple-protocol pool (so the multi-statement 0085
// file runs as a single Exec — the default extended protocol would run only the
// first statement), ensures ref_schema exists, then applies the migration
// verbatim. The migration is idempotent (CREATE … IF NOT EXISTS + INSERT … ON
// CONFLICT DO NOTHING), so re-running it across a shared container is safe.
func setupShippingSeed(dsn string) (*pgxpool.Pool, error) {
	ctx := context.Background()
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	cfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	if _, err := pool.Exec(ctx, `CREATE SCHEMA IF NOT EXISTS ref_schema`); err != nil {
		pool.Close()
		return nil, err
	}
	mig, err := os.ReadFile(shippingMigration)
	if err != nil {
		pool.Close()
		return nil, err
	}
	if _, err := pool.Exec(ctx, string(mig)); err != nil {
		pool.Close()
		return nil, err
	}
	return pool, nil
}

func TestLookupTransit_FromSeed(t *testing.T) {
	repo := shippingRepo(t)
	ctx := context.Background()

	// Expected values are DERIVED from the 0085 matrix (not assumed): tiers
	// marmara/ege=1, ic_anadolu/akdeniz/karadeniz=2, dogu/guneydogu=3;
	// min = same?1:GREATEST(2,1+|Δtier|); max = same?2:min+1+(destTier==3?1:0).
	cases := []struct {
		name             string
		origin, dest     string
		wantMin, wantMax int
	}{
		{"intra_zone_marmara", "istanbul", "istanbul", 1, 2},
		{"intra_zone_dogu", "erzurum", "van", 1, 2},
		{"t1_to_t1_cross_zone", "istanbul", "izmir", 2, 3},
		{"t1_to_t2", "istanbul", "ankara", 2, 3},
		{"t2_to_t2_cross_zone", "adana", "trabzon", 2, 3},
		{"t1_to_akdeniz", "istanbul", "antalya", 2, 3},
		{"t1_to_t3_eastbound", "istanbul", "diyarbakir", 3, 5},
		// Asymmetric: west-bound from the east does NOT add the eastern-tier day.
		{"t3_to_t1_westbound", "diyarbakir", "istanbul", 3, 4},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			minD, maxD, found, err := repo.LookupTransit(ctx, "TR", tc.origin, tc.dest)
			if err != nil {
				t.Fatalf("LookupTransit: %v", err)
			}
			if !found {
				t.Fatalf("LookupTransit(%s→%s): found=false, want a seeded pair", tc.origin, tc.dest)
			}
			if minD != tc.wantMin || maxD != tc.wantMax {
				t.Errorf("LookupTransit(%s→%s): got %d-%d, want %d-%d",
					tc.origin, tc.dest, minD, maxD, tc.wantMin, tc.wantMax)
			}
		})
	}
}

func TestLookupTransitDefault_FromSeed(t *testing.T) {
	repo := shippingRepo(t)
	ctx := context.Background()

	minD, maxD, found, err := repo.LookupTransitDefault(ctx, "TR")
	if err != nil {
		t.Fatalf("LookupTransitDefault: %v", err)
	}
	if !found || minD != 2 || maxD != 5 {
		t.Errorf("LookupTransitDefault(TR): got %d-%d found=%v, want 2-5 found=true", minD, maxD, found)
	}

	// Unknown market → no fallback row → found=false (no error).
	if _, _, found, err := repo.LookupTransitDefault(ctx, "XX"); err != nil || found {
		t.Errorf("LookupTransitDefault(XX): found=%v err=%v, want found=false nil", found, err)
	}
}

func TestLookupTransit_UnknownFallsBack(t *testing.T) {
	repo := shippingRepo(t)
	ctx := context.Background()

	// found=false (not an error) on any join miss — the signal EstimateETA uses
	// to fall back to LookupTransitDefault.
	cases := []struct {
		name         string
		market       string
		origin, dest string
	}{
		{"unknown_dest", "TR", "istanbul", "atlantis"},
		{"unknown_origin", "TR", "atlantis", "istanbul"},
		{"unknown_market", "XX", "istanbul", "izmir"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			minD, maxD, found, err := repo.LookupTransit(ctx, tc.market, tc.origin, tc.dest)
			if err != nil {
				t.Fatalf("LookupTransit: %v", err)
			}
			if found || minD != 0 || maxD != 0 {
				t.Errorf("LookupTransit(%s %s→%s): got %d-%d found=%v, want 0-0 found=false",
					tc.market, tc.origin, tc.dest, minD, maxD, found)
			}
		})
	}
}
