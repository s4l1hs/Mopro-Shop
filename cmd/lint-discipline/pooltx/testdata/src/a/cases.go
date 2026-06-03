package a

import (
	"context"

	"pgxpool"
)

func violationBasic(ctx context.Context, pool *pgxpool.Pool) {
	tx, _ := pool.Begin(ctx)
	_, _ = pool.Exec(ctx, "INSERT ...") // want `pool-acquire-inside-tx`
	_ = tx
}

func okBeforeTx(ctx context.Context, pool *pgxpool.Pool) {
	_, _ = pool.Exec(ctx, "SELECT ...") // before Begin — fine
	tx, _ := pool.Begin(ctx)
	_ = tx
}

func okInDefer(ctx context.Context, pool *pgxpool.Pool) {
	tx, _ := pool.Begin(ctx)
	defer pool.Exec(ctx, "cleanup") // post-commit defer — fine
	_ = tx
}

func violationInGoroutine(ctx context.Context, pool *pgxpool.Pool) {
	tx, _ := pool.Begin(ctx)
	go func() {
		_, _ = pool.Query(ctx, "SELECT ...") // want `pool-acquire-inside-tx`
	}()
	_ = tx
}

func okNoTx(ctx context.Context, pool *pgxpool.Pool) {
	_, _ = pool.Exec(ctx, "INSERT ...") // no tx opened here — fine
}

func okAfterRollback(ctx context.Context, pool *pgxpool.Pool) {
	tx, _ := pool.Begin(ctx)
	if false {
		_ = tx.Rollback(ctx)
		_, _ = pool.Exec(ctx, "SELECT ...") // after Rollback — tx closed — fine
		return
	}
	_ = tx.Commit(ctx)
}
