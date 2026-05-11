#!/usr/bin/env bash
set -euo pipefail

HOOKS_DIR="$(git rev-parse --git-dir)/hooks"

cat > "${HOOKS_DIR}/pre-push" << 'HOOK'
#!/usr/bin/env bash
make verify
HOOK

chmod +x "${HOOKS_DIR}/pre-push"
echo "pre-push hook installed at ${HOOKS_DIR}/pre-push"
