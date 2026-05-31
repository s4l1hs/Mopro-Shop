#!/usr/bin/env bash
# tool/audit/list_endpoints.sh
#
# PURPOSE
#   Inventory every HTTP endpoint the platform exposes, across both routing
#   styles in use:
#     1. core-svc hand-registered routes  — `mux.Handle("METHOD /path", ...)`
#        in cmd/core-svc/*.go (Go 1.22 net/http method patterns).
#     2. OpenAPI-declared operations       — api/openapi.yaml (fin-svc is wired
#        from the generated strict handler, so its surface == the spec).
#   For every hand-registered route it flags whether the same method+path is
#   declared in the OpenAPI spec ("documented") or is a hand-written endpoint
#   that lives only in code.
#
# OUTPUT
#   GitHub-flavoured Markdown to stdout. Two tables: (A) code-registered routes
#   with file:line + OpenAPI coverage, (B) OpenAPI operation catalogue.
#   Deterministic: routes are sorted; re-running on an unchanged tree is a no-op.
#
# USAGE
#   tool/audit/list_endpoints.sh            # markdown to stdout
#   tool/audit/list_endpoints.sh --help
#
# EXTEND
#   If a fourth service starts hand-registering routes, add its cmd/<svc> dir to
#   $SCAN_DIRS. If the spec moves, update $OPENAPI.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
OPENAPI="api/openapi.yaml"
SCAN_DIRS="cmd/core-svc cmd/fin-svc cmd/jobs-svc"

# --- Extract OpenAPI method+path pairs (lowercased "method /path") ----------
openapi_pairs() {
  [ -f "$OPENAPI" ] || return 0
  awk '
    /^paths:/ { inpaths=1; next }
    inpaths && /^[a-zA-Z]/ { inpaths=0 }           # left the paths: block
    inpaths && /^  \/[^ ]+:/ {
      p=$1; sub(/:$/,"",p); path=p; next
    }
    inpaths && /^    (get|post|put|patch|delete):/ {
      m=$1; sub(/:$/,"",m); printf "%s %s\n", m, path
    }
  ' "$OPENAPI" | sort -u
}

# --- Extract OpenAPI operationIds keyed by "method /path" -------------------
openapi_ops_table() {
  [ -f "$OPENAPI" ] || { echo "_OpenAPI spec not found at $OPENAPI._"; return 0; }
  awk '
    /^paths:/ { inpaths=1; next }
    inpaths && /^[a-zA-Z]/ { inpaths=0 }
    inpaths && /^  \/[^ ]+:/ { p=$1; sub(/:$/,"",p); path=p; next }
    inpaths && /^    (get|post|put|patch|delete):/ { m=toupper($1); sub(/:$/,"",m); cur=m" "path; next }
    inpaths && /^      operationId:/ { print cur" | "$2 }
  ' "$OPENAPI" | sort
}

OPENAPI_PAIRS="$(openapi_pairs)"

is_documented() {
  # $1 = METHOD  $2 = /path  -> "yes"/"no" (path templating normalised)
  local key
  key="$(printf '%s %s' "$(echo "$1" | tr 'A-Z' 'a-z')" "$2" | sed -E 's/\{[^}]+\}/{}/g')"
  local norm
  norm="$(printf '%s\n' "$OPENAPI_PAIRS" | sed -E 's/\{[^}]+\}/{}/g')"
  if printf '%s\n' "$norm" | grep -qxF "$key"; then echo yes; else echo no; fi
}

echo "### A. Code-registered routes (core-svc & friends)"
echo
echo "| Method | Path | Service | File:Line | In OpenAPI |"
echo "|---|---|---|---|---|"
# grep every mux.Handle("METHOD /path"  /  mux.HandleFunc("METHOD /path"
grep -rnoE 'mux\.Handle(Func)?\("(GET|POST|PUT|PATCH|DELETE) [^"]+"' $SCAN_DIRS 2>/dev/null \
  | sed -E 's/mux\.Handle(Func)?\("//; s/"$//' \
  | sort -t: -k1,1 -k2,2n \
  | while IFS= read -r line; do
      file="${line%%:*}"; rest="${line#*:}"
      lno="${rest%%:*}"; route="${rest#*:}"
      method="${route%% *}"; path="${route#* }"
      svc="$(echo "$file" | sed -E 's#cmd/([^/]+)/.*#\1#')"
      doc="$(is_documented "$method" "$path")"
      echo "| $method | \`$path\` | $svc | \`$file:$lno\` | $doc |"
    done

echo
echo "### B. OpenAPI operation catalogue (\`$OPENAPI\`)"
echo
echo "| Method+Path | operationId |"
echo "|---|---|"
openapi_ops_table | while IFS= read -r row; do
  mp="${row% | *}"; op="${row#* | }"
  echo "| \`$mp\` | $op |"
done

echo
total_code="$(grep -rhoE 'mux\.Handle(Func)?\("(GET|POST|PUT|PATCH|DELETE) ' $SCAN_DIRS 2>/dev/null | wc -l | tr -d ' ')"
total_oapi="$(printf '%s\n' "$OPENAPI_PAIRS" | grep -c . || true)"
echo "_Totals: ${total_code} code-registered routes; ${total_oapi} OpenAPI operations._"
