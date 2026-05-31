#!/usr/bin/env bash
# tool/audit/smoke_test.sh
#
# PURPOSE
#   Smoke-test the audit inventory scripts (§13.1). For each script it asserts:
#     (1) the script runs and exits 0,
#     (2) it produces non-empty Markdown,
#     (3) it is deterministic — two consecutive runs are byte-identical.
#   Also runs `regen.sh --check` so a stale SYSTEM_AUDIT.md fails the suite.
#
# USAGE
#   tool/audit/smoke_test.sh            # prints PASS/FAIL per script
#   tool/audit/smoke_test.sh --help
#
# Exit code is non-zero if any assertion fails.
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
A="tool/audit"
fail=0

# NAME|command
SCRIPTS=(
  "list_endpoints|bash $A/list_endpoints.sh"
  "list_routes|dart run $A/list_routes.dart"
  "list_providers|dart run $A/list_providers.dart"
  "dump_schema|bash $A/dump_schema.sh"
  "check_i18n|bash $A/check_i18n.sh"
)

for s in "${SCRIPTS[@]}"; do
  name="${s%%|*}"; cmd="${s#*|}"
  out1="$(mktemp)"; out2="$(mktemp)"
  if ! $cmd > "$out1" 2>/dev/null; then
    echo "FAIL  $name — non-zero exit"; fail=1; rm -f "$out1" "$out2"; continue
  fi
  if [ ! -s "$out1" ]; then
    echo "FAIL  $name — empty output"; fail=1; rm -f "$out1" "$out2"; continue
  fi
  $cmd > "$out2" 2>/dev/null
  if ! diff -q "$out1" "$out2" >/dev/null; then
    echo "FAIL  $name — non-deterministic (two runs differ)"; fail=1
  else
    lines="$(wc -l < "$out1" | tr -d ' ')"
    echo "PASS  $name — ${lines} lines, deterministic"
  fi
  rm -f "$out1" "$out2"
done

echo "----"
if bash "$A/regen.sh" --check >/dev/null 2>&1; then
  echo "PASS  regen --check — SYSTEM_AUDIT.md up to date"
else
  echo "FAIL  regen --check — SYSTEM_AUDIT.md stale (run 'make audit')"; fail=1
fi

[ "$fail" -eq 0 ] && echo "ALL AUDIT SMOKE TESTS PASSED" || echo "AUDIT SMOKE TESTS FAILED"
exit "$fail"
