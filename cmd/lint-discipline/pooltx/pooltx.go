// Package pooltx implements the pool-acquire-inside-tx analyzer (TOOLING_AUDIT
// T-007). It flags a *pgxpool.Pool method call (Exec/Query/QueryRow/Acquire/
// Begin/BeginTx/SendBatch/CopyFrom) that occurs, within a single function, AFTER
// that pool's Begin/BeginTx opened a transaction — the pool-exhaustion / deadlock
// pattern fixed in PR #42 (cashback) and #47 (financial-domain sweep).
//
// Scope: same-function, position-ordered (sound for straight-line code, the real
// bug shape). False-positive guards: pool calls BEFORE the Begin are fine; pool
// calls inside a `defer` are assumed post-Commit/Rollback and ignored. A call
// inside a goroutine launched after Begin IS flagged (PR #42 flagged exactly that).
// Suppress a reviewed case with `//nolint:pool-acquire-inside-tx`.
package pooltx

import (
	"go/ast"
	"go/token"
	"go/types"
	"strings"

	"golang.org/x/tools/go/analysis"
)

var Analyzer = &analysis.Analyzer{
	Name: "poolacquireintx",
	Doc:  "flags *pgxpool.Pool use after a Begin/BeginTx within the same function (pool-acquire-inside-tx)",
	Run:  run,
}

// pool methods that acquire a connection from the pool (the exhaustion risk).
var poolMethods = map[string]bool{
	"Exec": true, "Query": true, "QueryRow": true, "Acquire": true,
	"Begin": true, "BeginTx": true, "SendBatch": true, "CopyFrom": true,
}

func isPoolType(t types.Type) bool {
	if t == nil {
		return false
	}
	// *pgxpool.Pool (or pgxpool.Pool) — match by the named type's string.
	return strings.Contains(t.String(), "pgxpool.Pool")
}

func run(pass *analysis.Pass) (interface{}, error) {
	for _, file := range pass.Files {
		for _, decl := range file.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			analyzeFunc(pass, fn)
		}
	}
	return nil, nil
}

// poolCall is a method call on a *pgxpool.Pool value.
type poolCall struct {
	pos     token.Pos
	method  string
	inDefer bool
}

func analyzeFunc(pass *analysis.Pass, fn *ast.FuncDecl) {
	var calls []poolCall
	var txClose []token.Pos // positions of .Commit / .Rollback calls (tx closed)
	deferDepth := 0

	record := func(n ast.Node, depth int) {
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return
		}
		sel, ok := call.Fun.(*ast.SelectorExpr)
		if !ok {
			return
		}
		if sel.Sel.Name == "Commit" || sel.Sel.Name == "Rollback" {
			txClose = append(txClose, call.Pos())
			return
		}
		if poolMethods[sel.Sel.Name] && isPoolType(pass.TypesInfo.TypeOf(sel.X)) {
			calls = append(calls, poolCall{pos: call.Pos(), method: sel.Sel.Name, inDefer: depth > 0})
		}
	}

	var visit func(n ast.Node) bool
	visit = func(n ast.Node) bool {
		if n == nil {
			return false
		}
		if _, ok := n.(*ast.DeferStmt); ok {
			deferDepth++
			ast.Inspect(n, func(m ast.Node) bool {
				if m != n {
					record(m, deferDepth)
				}
				return true
			})
			deferDepth--
			return false
		}
		record(n, deferDepth)
		return true
	}
	ast.Inspect(fn.Body, visit)

	// Earliest tx-opening call (Begin/BeginTx) on a pool.
	txStart := token.NoPos
	for _, c := range calls {
		if (c.method == "Begin" || c.method == "BeginTx") && (txStart == token.NoPos || c.pos < txStart) {
			txStart = c.pos
		}
	}
	if txStart == token.NoPos {
		return // no tx opened from a pool in this function
	}
	for _, c := range calls {
		if c.pos <= txStart || c.inDefer {
			continue // before the tx opened, or in post-commit defer cleanup
		}
		if closedBefore(txClose, txStart, c.pos) {
			continue // a Commit/Rollback occurs before this call — tx already closed (safe)
		}
		pass.Reportf(c.pos, "pool-acquire-inside-tx: *pgxpool.Pool.%s called while a tx opened earlier in this function is in scope — acquire from the tx, not the pool (pool exhaustion; PR #42/#47)", c.method)
	}
}

// closedBefore reports whether a tx-close (Commit/Rollback) happens strictly
// between txStart and pos — meaning the tx is no longer open at pos.
func closedBefore(txClose []token.Pos, txStart, pos token.Pos) bool {
	for _, cp := range txClose {
		if cp > txStart && cp < pos {
			return true
		}
	}
	return false
}
