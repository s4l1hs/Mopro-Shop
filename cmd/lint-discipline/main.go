// Command lint-discipline runs the Mopro repo-discipline static analyzers
// (TOOLING_AUDIT T-007) that Steps 1–2 enforced by hand:
//
//   - pool-acquire-inside-tx   — pgxpool used while a tx is open (PR #42 / #47)
//   - soft-deleted-user-consumer — user read without a StatusDeleted guard (PR #49)
//
// A third check — idempotency-surface (financial INSERT without ON CONFLICT /
// FOR UPDATE) — is a SPLIT follow-up: SQL-shape analysis is FP-prone and deserves
// focused care rather than a mega-bundle commit (see docs/internal/lint-discipline.md).
//
// Usage: go run ./cmd/lint-discipline ./...     (or `make lint-discipline`)
// Built on golang.org/x/tools/go/analysis; each check is a separate Analyzer with
// analysistest coverage.
package main

import (
	"golang.org/x/tools/go/analysis/multichecker"

	"github.com/mopro/platform/cmd/lint-discipline/pooltx"
	"github.com/mopro/platform/cmd/lint-discipline/softdeleteduser"
)

func main() {
	multichecker.Main(
		pooltx.Analyzer,
		softdeleteduser.Analyzer,
	)
}
