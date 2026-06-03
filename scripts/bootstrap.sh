#!/usr/bin/env bash
# scripts/bootstrap.sh — one-command local setup for a fresh checkout (TOOLING_AUDIT T3-3).
#
# Gets a clean clone to a "ready to `make verify`" state. Idempotent — safe to
# re-run. Repo-local only: never sudo / never touches system packages. Toolchains
# (Go, Flutter, Docker) are DETECTED, not installed — it prints the install
# pointer and keeps going so you can see every gap in one pass.
#
# Usage: make bootstrap   (or: bash scripts/bootstrap.sh)
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

ok()   { printf '  \033[32m✅\033[0m %s\n' "$1"; }
skip() { printf '  \033[33m➡\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33m⚠\033[0m  %s\n' "$1"; }
MANUAL=()

echo "── Mopro bootstrap ──────────────────────────────────────────"

# 1. Toolchain detection (DETECTABLE — we don't install these).
echo "Toolchains:"
GO_WANT="$(awk '/^go /{print $2; exit}' go.mod)"
if command -v go >/dev/null 2>&1; then ok "go $(go version | awk '{print $3}' | sed 's/go//') (go.mod wants >= ${GO_WANT})"
else warn "go not found — install >= ${GO_WANT}: https://go.dev/dl/"; MANUAL+=("Install Go >= ${GO_WANT}"); fi
if command -v flutter >/dev/null 2>&1; then ok "flutter $(flutter --version 2>/dev/null | awk 'NR==1{print $2}')"
else warn "flutter not found — install 3.x: https://docs.flutter.dev/get-started/install"; MANUAL+=("Install Flutter 3.x"); fi
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ok "docker running (needed for integration tests)"
elif command -v docker >/dev/null 2>&1; then warn "docker installed but not running — start it for integration tests"; MANUAL+=("Start Docker daemon")
else warn "docker not found — needed for make verify integration suites: https://docs.docker.com/get-docker/"; MANUAL+=("Install Docker"); fi

# 2. Local env file (AUTOMATABLE, idempotent).
echo "Environment:"
if [ -f .env.local ]; then ok ".env.local exists"
elif [ -f .env.example ]; then cp .env.example .env.local; chmod 600 .env.local; ok ".env.local created from .env.example (chmod 600)"; MANUAL+=("Fill real values in .env.local")
else warn ".env.example missing — cannot scaffold .env.local"; fi

# 3. Go deps + git hooks (AUTOMATABLE).
echo "Backend:"
if command -v go >/dev/null 2>&1; then go mod download && ok "go mod download"; sh tool/setup-hooks.sh >/dev/null 2>&1 && ok "git hooks installed (.githooks/)" || warn "git hooks step failed (run 'make hooks')"
else skip "skipped go mod download + hooks (go missing)"; fi

# 4. Flutter deps (AUTOMATABLE).
echo "Mobile:"
if command -v flutter >/dev/null 2>&1; then
  (cd mobile && flutter pub get >/dev/null 2>&1) && ok "mobile: flutter pub get" || warn "mobile: flutter pub get failed"
  (cd mobile/packages/mopro_api && flutter pub get >/dev/null 2>&1) && ok "mopro_api: flutter pub get" || warn "mopro_api: flutter pub get failed"
else skip "skipped flutter pub get (flutter missing)"; fi

# 5. Summary.
echo "─────────────────────────────────────────────────────────────"
if [ ${#MANUAL[@]} -eq 0 ]; then
  echo "Bootstrap complete. Next: make verify"
else
  echo "Bootstrap done — remaining MANUAL steps (bootstrap can't do these):"
  for m in "${MANUAL[@]}"; do printf '  • %s\n' "$m"; done
  echo "Then: make verify"
fi
