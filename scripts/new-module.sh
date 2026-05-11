#!/usr/bin/env bash
# Creates the five-file stub skeleton for a new internal module.
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: new-module.sh internal/<name>" >&2
    exit 1
fi

DIR="$1"
NAME="$(basename "$DIR")"

mkdir -p "$DIR"

for file in api.go service.go repository.go domain.go errors.go; do
    if [ -f "${DIR}/${file}" ]; then
        echo "skip ${DIR}/${file} (already exists)"
        continue
    fi
    cat > "${DIR}/${file}" << EOF
package ${NAME}
EOF
    echo "created ${DIR}/${file}"
done

echo "module stub created at ${DIR}"
