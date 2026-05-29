#!/bin/sh
# setup-hooks: point this repo's hooks at .githooks/ and make scripts
# executable. Run once after clone (or via `make hooks`).

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true

current=$(git config --get core.hooksPath)
if [ "$current" = ".githooks" ]; then
  printf '✅ core.hooksPath = .githooks\n'
  printf '   active hooks: %s\n' "$(ls .githooks | tr '\n' ' ')"
else
  printf '❌ failed to set core.hooksPath (got: %s)\n' "$current" >&2
  exit 1
fi
