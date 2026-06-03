// Package softdeleteduser implements the soft-deleted-user-consumer analyzer
// (TOOLING_AUDIT T-007, PR #49). It flags a function that obtains an
// identity.User from a reader call and uses it, but contains NO `StatusDeleted`
// guard anywhere in the function body — the GetMe-style hole PR #49 closed.
//
// Scope: same-function heuristic. EXEMPT: repository.go (the dumb store legitimately
// returns rows without guarding — the SERVICE guards, per PR #49), *_test.go, and any
// function carrying a `//nolint:soft-deleted-user-consumer` comment (admin/audit reads
// that intentionally want deleted users). FP-prone by nature → wired continue-on-error.
package softdeleteduser

import (
	"go/ast"
	"go/types"
	"strings"

	"golang.org/x/tools/go/analysis"
)

var Analyzer = &analysis.Analyzer{
	Name: "softdeleteduserconsumer",
	Doc:  "flags a user read used without a StatusDeleted guard in the same function (soft-deleted-user-consumer)",
	Run:  run,
}

const guardConst = "StatusDeleted"
const nolintDirective = "nolint:soft-deleted-user-consumer"

var readerPrefixes = []string{"Get", "Find", "Resolve", "Lookup"}

// isReaderCall reports whether call reads an existing user from the REPOSITORY
// (the unguarded source). Two conditions: (a) a reader method name
// (Get*/Find*/Resolve*/Lookup* — not Create/Mark that yield a fresh user), and
// (b) the receiver is a *Repository. Consuming the SERVICE (e.g. svc.GetMe) is
// safe — the service guards internally (PR #49) — so those are not flagged; the
// risk is reading the repo directly without then guarding.
func isReaderCall(pass *analysis.Pass, call *ast.CallExpr) bool {
	sel, ok := call.Fun.(*ast.SelectorExpr)
	if !ok {
		return false
	}
	isReader := false
	for _, p := range readerPrefixes {
		if strings.HasPrefix(sel.Sel.Name, p) {
			isReader = true
			break
		}
	}
	if !isReader {
		return false
	}
	rt := pass.TypesInfo.TypeOf(sel.X)
	return rt != nil && strings.Contains(rt.String(), "Repository")
}

func isUser(t types.Type) bool {
	return t != nil && strings.HasSuffix(t.String(), "identity.User")
}

func isBlank(e ast.Expr) bool {
	id, ok := e.(*ast.Ident)
	return ok && id.Name == "_"
}

// userBoundToRealVar reports whether call returns an identity.User that is
// assigned to a non-blank LHS variable (a discarded `_` user is just an
// existence check, not a consumer).
func userBoundToRealVar(pass *analysis.Pass, call *ast.CallExpr, lhs []ast.Expr) bool {
	t := pass.TypesInfo.TypeOf(call)
	tup, ok := t.(*types.Tuple)
	if !ok {
		return isUser(t) && len(lhs) == 1 && !isBlank(lhs[0])
	}
	if tup.Len() != len(lhs) {
		return false // can't map result→LHS positions reliably
	}
	for i := 0; i < tup.Len(); i++ {
		if isUser(tup.At(i).Type()) && !isBlank(lhs[i]) {
			return true
		}
	}
	return false
}

func run(pass *analysis.Pass) (interface{}, error) {
	for _, file := range pass.Files {
		fname := pass.Fset.Position(file.Pos()).Filename
		if strings.HasSuffix(fname, "_test.go") || strings.HasSuffix(fname, "repository.go") {
			continue // dumb store + tests are exempt
		}
		for _, decl := range file.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			if hasGuard(fn) || hasNolint(fn, file) {
				continue
			}
			// Report the first unguarded reader-read of a User bound to a real var.
			ast.Inspect(fn.Body, func(n ast.Node) bool {
				as, ok := n.(*ast.AssignStmt)
				if !ok || len(as.Rhs) != 1 {
					return true
				}
				call, ok := as.Rhs[0].(*ast.CallExpr)
				if !ok || !isReaderCall(pass, call) {
					return true
				}
				// Find which result is the User, and require its LHS to be non-blank.
				if userBoundToRealVar(pass, call, as.Lhs) {
					pass.Reportf(call.Pos(), "soft-deleted-user-consumer: identity.User read here but no %s guard in this function — check Status before use, or //%s if intentional (PR #49)", guardConst, nolintDirective)
					return false
				}
				return true
			})
		}
	}
	return nil, nil
}

func hasGuard(fn *ast.FuncDecl) bool {
	found := false
	ast.Inspect(fn.Body, func(n ast.Node) bool {
		if id, ok := n.(*ast.Ident); ok && id.Name == guardConst {
			found = true
			return false
		}
		return true
	})
	return found
}

func hasNolint(fn *ast.FuncDecl, file *ast.File) bool {
	// NOTE: CommentGroup.Text() strips `//directive`-style comments, so check the
	// RAW comment text (c.Text) for the nolint directive.
	if fn.Doc != nil {
		for _, c := range fn.Doc.List {
			if strings.Contains(c.Text, nolintDirective) {
				return true
			}
		}
	}
	for _, cg := range file.Comments {
		if cg.Pos() > fn.Pos() && cg.End() < fn.End() {
			for _, c := range cg.List {
				if strings.Contains(c.Text, nolintDirective) {
					return true
				}
			}
		}
	}
	return false
}
