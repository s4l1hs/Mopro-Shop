#!/usr/bin/env bash
# scripts/lint-migrations.sh — migration-safety gate (TOOLING_AUDIT T3-4).
#
# Flags risky destructive DDL in FORWARD migrations (*.up.sql). Deliberately does
# NOT scan *.down.sql — a down migration legitimately reverses/DROPs (95 such DROPs
# live there; flagging them would be all false positives). Risky = DROP COLUMN /
# DROP TABLE (data loss) / SET NOT NULL (rewrite + fails on existing nulls). NOT
# risky (relaxing / backward-compatible, never flagged): DROP NOT NULL, DROP
# CONSTRAINT (e.g. dropping a CHECK loosens validation — the repo has 2 such in
# up.sql). Ratchets against a baseline so reviewed cases don't block; any NEW
# risky line fails --strict.
#
# Usage:
#   scripts/lint-migrations.sh            # list risky *.up.sql DDL (report only)
#   scripts/lint-migrations.sh --strict   # exit 1 on drift from the baseline (CI)
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

BASELINE="tool/audit/migration_safety_baseline.txt"
STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

RISKY='DROP[[:space:]]+(COLUMN|TABLE)|SET[[:space:]]+NOT[[:space:]]+NULL'

# Findings as "<relpath>: <normalized-sql>" (line number stripped so the baseline
# survives line shifts). DROP NOT NULL never matches RISKY (it's not SET NOT NULL
# nor DROP COLUMN/TABLE/CONSTRAINT).
found="$(grep -rniE "$RISKY" --include='*.up.sql' migrations/ 2>/dev/null \
  | sed -E 's/:[0-9]+:/: /; s/[[:space:]]+/ /g; s/^ +//; s/ +$//' \
  | sort -u || true)"
base="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$BASELINE" 2>/dev/null | sort -u || true)"

if [ -n "$found" ]; then
  echo "Risky DDL in forward migrations (*.up.sql):"
  printf '%s\n' "$found"
else
  echo "migration-safety: no risky DDL in *.up.sql."
fi

if [ "$STRICT" -eq 1 ]; then
  drift="$(comm -23 <(printf '%s\n' "$found" | grep -vE '^$' || true) <(printf '%s\n' "$base"))"
  if [ -n "$drift" ]; then
    echo >&2
    echo "migration-safety --strict: NEW risky DDL in a forward migration (not in $BASELINE):" >&2
    printf '  %s\n' $drift >&2
    echo "Use a soft-deprecation window (deprecate -> backfill -> drop later), or if reviewed-safe add it to the baseline." >&2
    exit 1
  fi
fi

# ── Duplicate version-number guard ───────────────────────────────────────────
# Two parallel lanes can each add migration NNNN and both be green alone —
# golang-migrate then fails on main with "duplicate migration version" (Batch B:
# 0094_checkout_installments × 0094_membership_tiers). Catch the collision here
# (this lint runs in verify-fast + CI), per-directory, on *.up.sql.
dups=""
for dir in migrations/ecom migrations/ledger; do
  [ -d "$dir" ] || continue
  d="$(ls "$dir"/*.up.sql 2>/dev/null | sed -E 's#.*/([0-9]+)_.*#\1#' | sort | uniq -d)"
  [ -n "$d" ] && dups="$dups$dir: $(echo "$d" | tr '\n' ' ')\n"
done
if [ -n "$dups" ]; then
  echo >&2
  echo "migration-safety: DUPLICATE migration version numbers (golang-migrate will refuse to run):" >&2
  printf "  %b" "$dups" >&2
  echo "Renumber the later-merged migration to the next free version." >&2
  exit 1
fi
echo "migration-safety: no duplicate version numbers."
