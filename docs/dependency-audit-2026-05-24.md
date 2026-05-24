# Dependency Audit — 2026-05-24

Performed as Phase D of the pre-launch hygiene batch.

---

## Go module

**Module:** `github.com/mopro/platform`
**Go toolchain:** `go 1.25.0`

### go mod tidy

`go mod tidy` was run after deleting 5 dead `pkg/` stubs (Phase B). Changes:

- Several previously-indirect transitive deps were reclassified (direct ↔ indirect) as the import graph updated.
- `go.opentelemetry.io/contrib/bridges/otelslog` and `go.opentelemetry.io/contrib/propagators/b3` removed (no longer in import graph after pkg stub deletion).
- `go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.61.0` added (direct, pulled by active internal packages).
- `go-test/deep` added as indirect (test utility).

Build and full test suite (`go test -race ./...`) passed with clean output after tidy.

### govulncheck

Tool: `golang.org/x/vuln/cmd/govulncheck@v1.3.0`

**Before patch:** 19 CVEs found in modules `golang.org/x/crypto@v0.51.0` and `golang.org/x/net@v0.53.0`. govulncheck confirmed **0 vulnerable call sites** in our code (all affected symbols are in unused package paths).

**Action taken:** Updated both packages to latest patch releases:

| Module | Before | After |
|---|---|---|
| `golang.org/x/crypto` | v0.51.0 | v0.52.0 |
| `golang.org/x/net` | v0.53.0 | v0.55.0 |
| `golang.org/x/sys` | v0.44.0 | v0.45.0 (transitive) |

**After patch:** `govulncheck ./...` → `No vulnerabilities found.`

---

## Flutter

**Toolchain:** Flutter 3.x (pinned in `mobile/.metadata`, channel stable)

`flutter` binary was not available in the current development environment. Manual review of `mobile/pubspec.yaml` shows:

| Package | Constraint | Latest (pub.dev, ~2026-05-24) | Status |
|---|---|---|---|
| `dio` | ^5.7.0 | 5.8.x | patch available |
| `go_router` | ^14.2.0 | 14.x | ✅ current range |
| `flutter_riverpod` | ^2.5.1 | 2.6.x | minor available |
| `flutter_secure_storage` | ^9.2.2 | 9.2.x | ✅ current |
| `easy_localization` | ^3.0.7 | 3.0.7 | ✅ current |
| `webview_flutter` | ^4.10.0 | 4.10.x | ✅ current |
| `json_annotation` | ^4.9.0 | 4.9.0 | ✅ current |

**Recommendation:** Run `flutter pub upgrade` in `mobile/` before launch to pull latest compatible patch releases. No breaking changes expected within the `^` constraints.

---

## Summary

| Check | Result |
|---|---|
| `go mod tidy` | ✅ Clean, stale entries removed |
| `govulncheck` | ✅ 0 vulnerabilities after patch |
| Flutter pubspec | ⚠️ Patch upgrades available (non-breaking) |
| Flutter `pub outdated` | ⚠️ Could not run — `flutter` not in PATH |
