# Cleanup audit — raw analyzer outputs (evidence for CLEANUP_AUDIT.md)

Captured at main@ca739bf4 (2026-06-02). Tools: staticcheck 2026.1 (v0.7.0),
golang.org/x/tools deadcode, golangci-lint 2.12.2, flutter 3.44 / dart 3.12.

- `go_staticcheck_U1000.txt` — unused (unexported) Go symbols. CONFIRMED dead.
- `go_deadcode_test.txt` — whole-program unreachable funcs (roots = all mains + tests).
  NOTE: 41 lines are internal/api/core_impl.go (intentional 501-stub, see audit §3);
  7 lines are web/node_modules/** (NOT git-tracked → false positive, excluded).
- `go_mod_tidy_diff.txt` — EMPTY = go.mod is tidy (no unused requires).
- `dart_flutter_analyze.txt` — "No issues found!" (very_good_analysis, strict).
- `dart_dead_classes.txt` / `dart_dead_providers.txt` — grep cross-file scans.
  HIGH false-positive rate for Riverpod Notifier/State/provider classes
  (file-internal composition + type inference defeat grep). Actual-widget
  entries are credible; verified subset in audit §5. Candidate pool, not a dead list.
- `dart_unused_i18n_keys.txt` — 192 full-string-unmatched keys; HIGH FP
  (easy_localization builds keys by prefix/interpolation). Manual review only.
- `dart_orphan_goldens.txt` — stems unreferenced; HIGH FP (interpolated golden
  names e.g. refund_card_${status}); failures/ entries are gitignored debris.
- `dart_unused_assets.txt` — EMPTY (no unused images/data).
- `dart_unused_pubspec_deps.txt` — see audit §6; carousel_slider/fl_chart/
  json_annotation confirmed 0-import; cupertino_icons implicit (keep).
