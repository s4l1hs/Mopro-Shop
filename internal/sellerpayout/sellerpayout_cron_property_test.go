//go:build integration

package sellerpayout_test

import (
	"context"
	"fmt"
	"reflect"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/internal/sellerpayout"
)

// propPayoutCounter provides unique seller IDs for property test iterations,
// offset from the seqCounter used by uniqueID() to avoid collisions within
// a single test binary run.
var propPayoutCounter atomic.Int64

func propPayoutSellerID() int64 {
	return time.Now().UnixMilli()*1_000_000 + 500_000 + propPayoutCounter.Add(1)
}

// propPayoutCleanup deletes all DB rows created by one property test iteration.
// Deletion order respects the FK: seller_payouts (referencing) → payout_batches
// (referenced). Ledger entries are append-only and are intentionally left intact.
func propPayoutCleanup(pool *pgxpool.Pool, ctx context.Context, sellerID int64) {
	pool.Exec(ctx, `DELETE FROM commission_schema.seller_payouts WHERE seller_id=$1`, sellerID)
	pool.Exec(ctx, `DELETE FROM commission_schema.payout_batches WHERE seller_id=$1`, sellerID)
	pool.Exec(ctx, `DELETE FROM commission_schema.seller_psp_accounts WHERE seller_id=$1`, sellerID)
}

// TestCronProperty_BatchingAggregation is a 500-iteration property test that
// verifies the following invariants for any N ∈ [1, 50] scheduled payouts for
// a single (seller_id, currency, payout_date) combination:
//
//  1. Exactly 1 payout_batches row exists with status='paid' for (seller, date, ccy).
//  2. batch.total_amount_minor == SUM(individual payout.amount_minor).
//  3. All N seller_payouts rows have status='paid' and the same non-NULL batch_id.
//  4. Exactly 1 wallet_schema.outbox row keyed by the batch idempotency key.
//  5. Ledger debit (D) entries for the batch transaction sum to total_amount_minor.
//  6. Ledger credit (C) entries for the batch transaction sum to total_amount_minor
//     (double-entry D=C invariant per CLAUDE.md § 4.1).
func TestCronProperty_BatchingAggregation(t *testing.T) {
	pool := setupPool(t)
	ctx := context.Background()

	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 500

	properties := gopter.NewProperties(params)

	// Generator: produce a []int64 of length N (1..50) where each element is an
	// amount in [100, 1_000_000] minor units (1 kuruş to 10 000 TRY per payout).
	amountsGen := gen.IntRange(1, 50).FlatMap(
		func(v interface{}) gopter.Gen {
			n := v.(int)
			return gen.SliceOfN(n, gen.Int64Range(100, 1_000_000))
		},
		reflect.TypeOf([]int64{}),
	)

	properties.Property(
		"N payouts for 1 seller/date/ccy → 1 paid batch, correct total, all payouts paid, "+
			"1 outbox row, ledger D=C=total",
		prop.ForAll(
			func(amounts []int64) bool {
				n := len(amounts)
				if n == 0 {
					return true
				}

				// Fresh seller_id per iteration — no cross-iteration interference.
				sellerID := propPayoutSellerID()
				payoutDate := time.Now().UTC().Truncate(24 * time.Hour)
				batchKey := sellerpayout.BatchIdempotencyKeyExported(sellerID, payoutDate, "TRY")

				// Clean up any 'scheduled' rows left over by previous iterations
				// before seeding, so FetchScheduledPayouts only sees this iteration's rows.
				cancelStaleScheduledPayouts(t, pool)

				seedPspAccount(t, pool, sellerID, fmt.Sprintf("prop_payout_member_%d", sellerID))

				var expectedTotal int64
				for i, amt := range amounts {
					uid := uniqueID()
					_, err := pool.Exec(ctx, `
						INSERT INTO commission_schema.seller_payouts
							(order_id, seller_id, amount_minor, currency,
							 delivered_at, unlock_at, status, market, idempotency_key)
						VALUES ($1,$2,$3,'TRY',
						        now()-interval '5 days', now()-interval '2 days',
						        'scheduled','TR',$4)`,
						uid, sellerID, amt,
						fmt.Sprintf("payout:order_%d:seller_%d:prop_%d", uid, sellerID, i),
					)
					if err != nil {
						t.Logf("seed payout %d: %v", i, err)
						propPayoutCleanup(pool, ctx, sellerID)
						return false
					}
					expectedTotal += amt
				}

				psp := &shadowPsp{}
				svc := setupService(t, pool, psp)

				res, err := svc.RunDailyPayouts(ctx, payoutDate, "TR", "TRY")
				if err != nil {
					t.Logf("RunDailyPayouts error: %v", err)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}
				if res.Batched != 1 || res.Failed != 0 {
					t.Logf("result: batched=%d failed=%d (want 1/0)", res.Batched, res.Failed)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}

				// ── Check 1+2: exactly 1 paid batch with correct total ─────────────
				var batchStatus string
				var dbTotal int64
				pool.QueryRow(ctx,
					`SELECT status, total_amount_minor
					 FROM commission_schema.payout_batches
					 WHERE seller_id=$1 AND payout_date=$2 AND currency='TRY'`,
					sellerID, payoutDate.Format("2006-01-02"),
				).Scan(&batchStatus, &dbTotal)
				if batchStatus != "paid" {
					t.Logf("batch status: want paid, got %q", batchStatus)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}
				if dbTotal != expectedTotal {
					t.Logf("batch total: want %d, got %d", expectedTotal, dbTotal)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}

				// ── Check 3: all N payouts status='paid', one shared batch_id ──────
				var paidCount, distinctBatchIDs int
				pool.QueryRow(ctx,
					`SELECT COUNT(*) FROM commission_schema.seller_payouts
					 WHERE seller_id=$1 AND status='paid'`, sellerID,
				).Scan(&paidCount)
				pool.QueryRow(ctx,
					`SELECT COUNT(DISTINCT batch_id) FROM commission_schema.seller_payouts
					 WHERE seller_id=$1 AND batch_id IS NOT NULL`, sellerID,
				).Scan(&distinctBatchIDs)
				if paidCount != n {
					t.Logf("paid payout count: want %d, got %d", n, paidCount)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}
				if distinctBatchIDs != 1 {
					t.Logf("distinct batch_ids: want 1, got %d", distinctBatchIDs)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}

				// ── Check 4: exactly 1 outbox row for this batch ──────────────────
				var outboxCount int
				pool.QueryRow(ctx,
					`SELECT COUNT(*) FROM wallet_schema.outbox WHERE idempotency_key=$1`,
					batchKey,
				).Scan(&outboxCount)
				if outboxCount != 1 {
					t.Logf("outbox rows: want 1, got %d", outboxCount)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}

				// ── Check 5+6: ledger D=C=expectedTotal (double-entry) ────────────
				var dTotal, cTotal int64
				pool.QueryRow(ctx,
					`SELECT COALESCE(SUM(le.amount_minor),0)
					 FROM wallet_schema.ledger_entries le
					 JOIN wallet_schema.transactions txn ON le.transaction_id = txn.id
					 WHERE txn.idempotency_key=$1 AND le.direction='D'`,
					batchKey,
				).Scan(&dTotal)
				pool.QueryRow(ctx,
					`SELECT COALESCE(SUM(le.amount_minor),0)
					 FROM wallet_schema.ledger_entries le
					 JOIN wallet_schema.transactions txn ON le.transaction_id = txn.id
					 WHERE txn.idempotency_key=$1 AND le.direction='C'`,
					batchKey,
				).Scan(&cTotal)
				if dTotal != expectedTotal || cTotal != expectedTotal {
					t.Logf("ledger: D=%d C=%d (want both=%d)", dTotal, cTotal, expectedTotal)
					propPayoutCleanup(pool, ctx, sellerID)
					return false
				}

				propPayoutCleanup(pool, ctx, sellerID)
				return true
			},
			amountsGen,
		),
	)

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}
