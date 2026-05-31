#!/usr/bin/env bash
# tool/audit/check_i18n.sh
#
# PURPOSE
#   Audit translation completeness. Flattens each locale JSON to dotted leaf-key
#   paths (via jq) and diffs every locale against the master locale (tr-TR, the
#   launch market). Reports per-locale: total keys, missing keys (present in
#   master, absent here), and extra keys (present here, absent in master).
#
# OUTPUT
#   GitHub-flavoured Markdown to stdout. Deterministic (sorted key sets).
#
# REQUIRES
#   jq (preinstalled on macOS via Xcode tools and on ubuntu-latest CI runners).
#
# USAGE
#   tool/audit/check_i18n.sh             # markdown summary to stdout
#   tool/audit/check_i18n.sh --list      # also print each missing key
#   tool/audit/check_i18n.sh --help
#
# EXTEND
#   $L10N_DIR = translations dir; $MASTER = master locale file basename.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
LIST=0
[ "${1:-}" = "--list" ] && LIST=1

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
L10N_DIR="mobile/assets/translations"
MASTER="tr-TR.json"

command -v jq >/dev/null 2>&1 || { echo "_check_i18n: jq not found._"; exit 0; }

flatten() { jq -r '[paths(scalars)|join(".")] | sort | .[]' "$1"; }

MASTER_PATH="$L10N_DIR/$MASTER"
[ -f "$MASTER_PATH" ] || { echo "_master locale not found: $MASTER_PATH_"; exit 0; }

master_keys="$(flatten "$MASTER_PATH")"
master_n="$(printf '%s\n' "$master_keys" | grep -c . || true)"

echo "### Translation completeness (master: \`$MASTER\`, $master_n keys)"
echo
echo "| Locale | Keys | Missing vs master | Extra vs master | Completeness |"
echo "|---|---|---|---|---|"

declare -a MISSING_DETAIL=()
for f in "$L10N_DIR"/*.json; do
  base="$(basename "$f")"
  keys="$(flatten "$f")"
  n="$(printf '%s\n' "$keys" | grep -c . || true)"
  if [ "$base" = "$MASTER" ]; then
    echo "| \`$base\` | $n | — | — | master |"
    continue
  fi
  missing="$(comm -23 <(printf '%s\n' "$master_keys") <(printf '%s\n' "$keys") || true)"
  extra="$(comm -13 <(printf '%s\n' "$master_keys") <(printf '%s\n' "$keys") || true)"
  nmiss="$(printf '%s\n' "$missing" | grep -c . || true)"
  nextra="$(printf '%s\n' "$extra" | grep -c . || true)"
  present=$(( master_n - nmiss ))
  pct=0
  [ "$master_n" -gt 0 ] && pct=$(( present * 100 / master_n ))
  echo "| \`$base\` | $n | $nmiss | $nextra | ${pct}% |"
  if [ "$nmiss" -gt 0 ]; then
    MISSING_DETAIL+=("$base|$missing")
  fi
done

if [ "$LIST" -eq 1 ]; then
  echo
  echo "#### Missing keys per locale"
  for entry in "${MISSING_DETAIL[@]:-}"; do
    [ -z "$entry" ] && continue
    base="${entry%%|*}"; keys="${entry#*|}"
    echo
    echo "<details><summary><code>$base</code></summary>"
    echo
    printf '%s\n' "$keys" | sed 's/^/- `/; s/$/`/'
    echo
    echo "</details>"
  done
fi
