// Minimal fake pgxpool for analysistest (type string contains "pgxpool.Pool").
package pgxpool

import "context"

type Tx interface {
	Commit(ctx context.Context) error
	Rollback(ctx context.Context) error
	Exec(ctx context.Context, sql string, args ...any) (any, error)
}
type Pool struct{}

func (p *Pool) Begin(ctx context.Context) (Tx, error)                        { return nil, nil }
func (p *Pool) BeginTx(ctx context.Context, o any) (Tx, error)               { return nil, nil }
func (p *Pool) Exec(ctx context.Context, sql string, a ...any) (any, error)  { return nil, nil }
func (p *Pool) Query(ctx context.Context, sql string, a ...any) (any, error) { return nil, nil }
func (p *Pool) Acquire(ctx context.Context) (any, error)                     { return nil, nil }
