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
#   tool/audit/check_i18n.sh --strict    # exit 1 if any locale has EXTRA keys
#   tool/audit/check_i18n.sh --help
#
# STRICT GATE (T-010)
#   --strict fails ONLY on extra keys (present in a locale, absent from master).
#   Extras are always drift: a typo'd key, or a key added to a locale but not the
#   tr-TR master. MISSING keys are deliberately NOT gated: per CLAUDE.md the only
#   launched market is TR, so non-master locales (ar/de/en) are partial by design
#   until their market launches. Gating missing keys would demand translating
#   unlaunched markets. CI wires --strict (see .github/workflows/flutter-ci.yml).
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
STRICT=0
for arg in "$@"; do
  case "$arg" in
    --list)   LIST=1 ;;
    --strict) STRICT=1 ;;
  esac
done

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
total_extra=0
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
  total_extra=$(( total_extra + nextra ))
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

# T-010 strict gate: extras are always drift (missing keys are by-design — see header).
if [ "$STRICT" -eq 1 ] && [ "$total_extra" -gt 0 ]; then
  echo >&2
  echo "check_i18n --strict: $total_extra extra key(s) present in a locale but absent from master ($MASTER)." >&2
  echo "Add them to the master locale or remove them from the offending locale." >&2
  exit 1
fi
