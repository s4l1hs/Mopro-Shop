//go:build integration

package order_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/order"
)

func setupReturnsSchema(ctx context.Context, pool *pgxpool.Pool, t *testing.T) {
	t.Helper()
	ddl := `
-- The shared TestMain orders DDL predates the v8 seller split; GetOrder selects
-- these columns, so add them if absent (no-op when already present).
ALTER TABLE order_schema.orders ADD COLUMN IF NOT EXISTS seller_id BIGINT;
ALTER TABLE order_schema.orders ADD COLUMN IF NOT EXISTS checkout_session_id TEXT;

DROP TABLE IF EXISTS order_schema.return_status_history CASCADE;
DROP TABLE IF EXISTS order_schema.return_items CASCADE;
DROP TABLE IF EXISTS order_schema.returns CASCADE;

CREATE TABLE order_schema.returns (
  id BIGSERIAL PRIMARY KEY, order_id BIGINT NOT NULL, user_id BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', reason TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
  refund_amount_minor BIGINT NOT NULL DEFAULT 0, refund_currency TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());

CREATE TABLE order_schema.return_items (
  id BIGSERIAL PRIMARY KEY,
  return_id BIGINT NOT NULL REFERENCES order_schema.returns(id) ON DELETE CASCADE,
  order_id BIGINT NOT NULL, order_item_id BIGINT NOT NULL, quantity INT NOT NULL CHECK (quantity >= 1),
  CONSTRAINT return_items_order_item_uniq UNIQUE (order_id, order_item_id));

CREATE TABLE order_schema.return_status_history (
  id BIGSERIAL PRIMARY KEY,
  return_id BIGINT NOT NULL REFERENCES order_schema.returns(id) ON DELETE CASCADE,
  status TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
`
	if _, err := pool.Exec(ctx, ddl); err != nil {
		t.Fatalf("returns schema setup: %v", err)
	}
}

// seedDeliveredOrder inserts a delivered order + one item, returns (orderID, itemID).
func seedDeliveredOrder(ctx context.Context, pool *pgxpool.Pool, t *testing.T, userID int64) (int64, int64) {
	t.Helper()
	var orderID int64
	delivered := time.Now().UTC().AddDate(0, 0, -1)
	err := pool.QueryRow(ctx,
		`INSERT INTO order_schema.orders
		   (user_id, status, subtotal_minor, total_minor, currency, delivered_at, idempotency_key)
		 VALUES ($1,'delivered',10000,10000,'TRY',$2,$3) RETURNING id`,
		userID, delivered, "ret-seed-"+time.Now().Format("150405.000000")).Scan(&orderID)
	if err != nil {
		t.Fatalf("seed order: %v", err)
	}
	var itemID int64
	err = pool.QueryRow(ctx,
		`INSERT INTO order_schema.order_items
		   (order_id, variant_id, seller_id, category_id, qty, unit_price_minor, unit_price_currency,
		    commission_pct_bps, kdv_pct_bps, commission_amount_minor, kdv_amount_minor, seller_net_minor)
		 VALUES ($1,1,10,5,1,10000,'TRY',1000,2000,1000,200,8800) RETURNING id`, orderID).Scan(&itemID)
	if err != nil {
		t.Fatalf("seed item: %v", err)
	}
	return orderID, itemID
}

// Concurrent return submissions for the same (order, item) converge to one row —
// same storage-layer-idempotency guarantee as the reviews helpful-vote test.
func TestIntegration_ConcurrentReturnSubmissionConverges(t *testing.T) {
	ctx := context.Background()
	setupReturnsSchema(ctx, integOrderPool, t)
	const userID = 4242
	orderID, itemID := seedDeliveredOrder(ctx, integOrderPool, t, userID)

	svc := order.NewReturnService(order.NewRepository(integOrderPool), order.NewReturnRepository(integOrderPool))

	const n = 8
	var wg sync.WaitGroup
	var mu sync.Mutex
	var okCount, dupCount, otherCount int
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func() {
			defer wg.Done()
			_, _, err := svc.CreateReturn(ctx, order.ReturnInput{
				OrderID: orderID, UserID: userID, Reason: order.ReasonDamaged,
				Items: []order.ReturnItemInput{{OrderItemID: itemID, Quantity: 1}},
			})
			mu.Lock()
			defer mu.Unlock()
			switch {
			case err == nil:
				okCount++
			case errors.Is(err, order.ErrReturnAlreadyExists),
				errors.Is(err, order.ErrQuantityExceedsReturn):
				// Both are valid "already returned" outcomes: racers that read
				// before the winner committed collide on the UNIQUE constraint;
				// racers that read after see zero returnable remaining.
				dupCount++
			default:
				otherCount++
				t.Errorf("unexpected error: %v", err)
			}
		}()
	}
	wg.Wait()

	if okCount != 1 {
		t.Errorf("okCount=%d want 1", okCount)
	}
	if otherCount != 0 {
		t.Errorf("otherCount=%d want 0", otherCount)
	}

	var rows int
	if err := integOrderPool.QueryRow(ctx,
		`SELECT COUNT(*) FROM order_schema.return_items WHERE order_id=$1 AND order_item_id=$2`,
		orderID, itemID).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Errorf("return_items rows=%d want exactly 1 (converged)", rows)
	}
}
