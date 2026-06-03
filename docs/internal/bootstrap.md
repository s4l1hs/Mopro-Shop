# Bootstrap — fresh-checkout setup (TOOLING_AUDIT T3-3)

`make bootstrap` (→ `scripts/bootstrap.sh`) takes a clean clone to a state where
`make verify` can run. Idempotent, repo-local (no sudo / no system packages).

## The from-zero path, classified

| Step | Class | Bootstrap does |
|---|---|---|
| Install Go (≥ go.mod `go` directive) | DETECTABLE | checks `go version`, prints install URL if missing |
| Install Flutter 3.x | DETECTABLE | checks `flutter --version`, prints install URL |
| Install + start Docker | DETECTABLE | checks `docker info`, prints pointer (needed for integration suites) |
| `.env.local` from `.env.example` | AUTOMATABLE | copies + `chmod 600` if absent |
| `go mod download` | AUTOMATABLE | runs it |
| Git hooks (`.githooks/`) | AUTOMATABLE | runs `tool/setup-hooks.sh` |
| `flutter pub get` (mobile + mopro_api) | AUTOMATABLE | runs both |
| Fill real `.env.local` values | MANUAL | listed in the closing summary |
| `make verify` | (final step) | the script tells you to run it |

DETECTABLE (not AUTOMATABLE) because installing a toolchain needs sudo / a
package manager / a version decision — out of a repo-local script's domain. The
script reports every gap in one pass (it doesn't stop at the first), so a new
contributor sees the full TODO immediately.

## What bootstrap deliberately does NOT do
- Install Go / Flutter / Docker (prints pointers).
- Fill secret values in `.env.local`.
- Bring up the DB stack — that's `make run-local` (app) / the test targets
  bring up their own ephemeral containers (`make verify`).

## Verify
`make bootstrap && make verify` on a fresh clone reaches green. Re-running
`make bootstrap` is a no-op on already-satisfied steps (idempotent).
