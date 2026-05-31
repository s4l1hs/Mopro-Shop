//go:build integration

package seller_test

// Integration tests for the seller repository + migration 0078 round-trip,
// against the same ephemeral PG16 as the catalog/order suites:
//
//	go test -tags=integration -v ./internal/seller/...
//
// Override DSN with SELLER_TEST_DSN if running against another endpoint.

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/seller"
)

const defaultTestDSN = "postgres://ecom_admin:test123@localhost:6433/mopro_ecom"

var integPool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("SELLER_TEST_DSN")
	if dsn == "" {
		dsn = defaultTestDSN
	}
	ctx := context.Background()
	var err error
	integPool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "seller integration: cannot create pool (%s): %v\n", dsn, err)
		os.Exit(1)
	}
	if err := integPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "seller integration: postgres ping failed: %v\n", err)
		os.Exit(1)
	}
	// Apply migration 0078 fresh (down then up) so the seed is deterministic.
	if err := runMigration(ctx, "../../migrations/ecom/0078_sellers.down.sql"); err != nil {
		fmt.Fprintf(os.Stderr, "seller integration: down migration: %v\n", err)
		os.Exit(1)
	}
	if err := runMigration(ctx, "../../migrations/ecom/0078_sellers.up.sql"); err != nil {
		fmt.Fprintf(os.Stderr, "seller integration: up migration: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	integPool.Close()
	os.Exit(code)
}

// runMigration executes a whole .sql file in one no-arg Exec, which pgx sends
// via the simple protocol (multi-statement support).
func runMigration(ctx context.Context, path string) error {
	sql, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	_, err = integPool.Exec(ctx, string(sql))
	return err
}

func TestIntegration_MigrationRoundTrip(t *testing.T) {
	ctx := context.Background()
	// up already applied in TestMain; verify the seed landed.
	var n int
	if err := integPool.QueryRow(ctx, `SELECT COUNT(*) FROM seller_schema.sellers`).Scan(&n); err != nil {
		t.Fatalf("count sellers: %v", err)
	}
	if n < 3 {
		t.Fatalf("seed: want >=3 sellers, got %d", n)
	}
	// down drops the tables; a follow-up query must error.
	if err := runMigration(ctx, "../../migrations/ecom/0078_sellers.down.sql"); err != nil {
		t.Fatalf("down: %v", err)
	}
	if _, err := integPool.Exec(ctx, `SELECT 1 FROM seller_schema.sellers LIMIT 1`); err == nil {
		t.Fatal("expected error querying dropped sellers table")
	}
	// Re-apply up so the rest of the suite has its fixtures.
	if err := runMigration(ctx, "../../migrations/ecom/0078_sellers.up.sql"); err != nil {
		t.Fatalf("re-up: %v", err)
	}
}

func TestIntegration_GetBySlug(t *testing.T) {
	ctx := context.Background()
	repo := seller.NewRepository(integPool)
	svc := seller.NewService(repo)

	s, err := svc.GetBySlug(ctx, "acme-store")
	if err != nil {
		t.Fatalf("GetBySlug: %v", err)
	}
	if s.ID != 1 || s.DisplayName != "Acme Store" {
		t.Errorf("seller mismatch: id=%d name=%q", s.ID, s.DisplayName)
	}
	if s.BioTranslations["tr"] == "" || s.BioTranslations["en"] == "" {
		t.Errorf("bio_translations not populated: %#v", s.BioTranslations)
	}

	if _, err := svc.GetBySlug(ctx, "does-not-exist"); !errors.Is(err, seller.ErrSellerNotFound) {
		t.Fatalf("unknown slug: want ErrSellerNotFound, got %v", err)
	}
}

func TestIntegration_SuspendedSellerHidden(t *testing.T) {
	ctx := context.Background()
	repo := seller.NewRepository(integPool)

	if _, err := integPool.Exec(ctx,
		`UPDATE seller_schema.sellers SET status='suspended' WHERE id=3`); err != nil {
		t.Fatalf("suspend: %v", err)
	}
	t.Cleanup(func() {
		_, _ = integPool.Exec(context.Background(),
			`UPDATE seller_schema.sellers SET status='active' WHERE id=3`)
	})

	if _, err := repo.GetByID(ctx, 3); !errors.Is(err, seller.ErrSellerNotFound) {
		t.Fatalf("suspended seller: want ErrSellerNotFound, got %v", err)
	}
}

func TestIntegration_SellerIDForUser(t *testing.T) {
	ctx := context.Background()
	repo := seller.NewRepository(integPool)
	svc := seller.NewService(repo)

	// user 1 is bound to seller 1 by the seed.
	id, isSeller, err := svc.ResolveSellerForUser(ctx, 1)
	if err != nil {
		t.Fatalf("ResolveSellerForUser(1): %v", err)
	}
	if !isSeller || id != 1 {
		t.Errorf("user 1: want (1,true), got (%d,%v)", id, isSeller)
	}

	// A user with no binding is not a seller.
	_, isSeller, err = svc.ResolveSellerForUser(ctx, 999999)
	if err != nil {
		t.Fatalf("ResolveSellerForUser(999999): %v", err)
	}
	if isSeller {
		t.Error("unbound user reported as seller")
	}
}
