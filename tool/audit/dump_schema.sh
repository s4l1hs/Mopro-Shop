#!/usr/bin/env bash
# tool/audit/dump_schema.sh
#
# PURPOSE
#   Inventory the database structure from committed SQL (NOT a live database).
#   Reading source rather than a running Postgres keeps output deterministic and
#   reproducible on any checkout — required for `make audit` to produce no diff.
#   Schemas come from the cluster bootstrap (deploy/postgres-*/init/*.sql);
#   tables and their owning migration come from migrations/*.
#
# OUTPUT
#   GitHub-flavoured Markdown to stdout. Deterministic (sorted).
#
# USAGE
#   tool/audit/dump_schema.sh             # markdown to stdout
#   tool/audit/dump_schema.sh --help
#
# EXTEND
#   $INIT_DIRS = schema bootstrap; $MIG_DIRS = migration roots.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
MIG_DIRS="migrations/ecom migrations/ledger"
INIT_DIRS="deploy/postgres-ecom/init deploy/postgres-ledger/init"

echo "### Schemas (CREATE SCHEMA in cluster bootstrap)"
echo
echo "| Schema | Cluster bootstrap file |"
echo "|---|---|"
{ grep -rinhoE 'CREATE SCHEMA( IF NOT EXISTS)? [a-z_]+' $INIT_DIRS 2>/dev/null || true; } \
  | sed -E 's/.*CREATE SCHEMA( IF NOT EXISTS)? //I' | sort -u \
  | while IFS= read -r sch; do
      [ -z "$sch" ] && continue
      first="$( { grep -rilE "CREATE SCHEMA( IF NOT EXISTS)? $sch\b" $INIT_DIRS 2>/dev/null || true; } | sort | head -1)"
      echo "| \`$sch\` | \`$(echo "${first:-?}" | sed "s#$ROOT/##")\` |"
    done

echo
echo "### Tables (CREATE TABLE in migrations + cluster bootstrap)"
echo
echo "| Schema.Table | Defined in |"
echo "|---|---|"
{ grep -rinoE 'CREATE TABLE( IF NOT EXISTS)? [a-z_]+\.[a-z_]+' $MIG_DIRS $INIT_DIRS 2>/dev/null || true; } \
  | while IFS= read -r line; do
      file="${line%%:*}"
      tbl="$(echo "$line" | sed -E 's/.*CREATE TABLE( IF NOT EXISTS)? //I')"
      echo "$tbl|$(basename "$file")"
    done | sort -u | while IFS='|' read -r tbl mig; do
      [ -z "$tbl" ] && continue
      echo "| \`$tbl\` | \`$mig\` |"
    done

echo
nsch="$( { grep -rihoE 'CREATE SCHEMA( IF NOT EXISTS)? [a-z_]+' $INIT_DIRS 2>/dev/null || true; } | sed -E 's/.*SCHEMA( IF NOT EXISTS)? //I' | sort -u | grep -c . || true)"
ntbl="$( { grep -rihoE 'CREATE TABLE( IF NOT EXISTS)? [a-z_]+\.[a-z_]+' $MIG_DIRS $INIT_DIRS 2>/dev/null || true; } | sed -E 's/.*TABLE( IF NOT EXISTS)? //I' | sort -u | grep -c . || true)"
nup="$(find $MIG_DIRS -name '*.up.sql' 2>/dev/null | wc -l | tr -d ' ')"
ndown="$(find $MIG_DIRS -name '*.down.sql' 2>/dev/null | wc -l | tr -d ' ')"
echo "_Totals: ${nsch} schemas, ${ntbl} tables; ${nup} up / ${ndown} down migrations._"
