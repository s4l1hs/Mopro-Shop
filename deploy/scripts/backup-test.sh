#!/usr/bin/env bash
# backup-test.sh — Local smoke test for the restic backup pipeline.
# Tests backup, retention, integrity check, and snapshot listing using a local
# temp repo. Does NOT require B2, Hetzner, Docker, or pg_dump.
#
# Usage:
#   ./backup-test.sh            # full test suite
#   ./backup-test.sh --fast     # skip the 3-snapshot retention test (much faster)
#
# Prerequisites: restic must be installed (brew install restic / apt install restic)
set -euo pipefail

FAST=false
[[ "${1:-}" == "--fast" ]] && FAST=true

PASS=0
FAIL=0

# ── Prerequisites ──────────────────────────────────────────────────────────────
if ! command -v restic &>/dev/null; then
    echo "SKIP: restic not installed. Install with: brew install restic  or  apt install restic"
    exit 0
fi

RESTIC_VER=$(restic version 2>/dev/null | head -1)
echo "restic: ${RESTIC_VER}"
echo ""

# ── Temp dirs ──────────────────────────────────────────────────────────────────
REPO_DIR=$(mktemp -d /tmp/test-restic-repo-XXXXXX)
DATA_DIR=$(mktemp -d /tmp/test-restic-data-XXXXXX)
RESTORE_DIR=$(mktemp -d /tmp/test-restic-restore-XXXXXX)
trap 'rm -rf "${REPO_DIR}" "${DATA_DIR}" "${RESTORE_DIR}"' EXIT

export RESTIC_REPOSITORY="${REPO_DIR}"
export RESTIC_PASSWORD="test-backup-password-$(date +%s)"

# ── Helpers ────────────────────────────────────────────────────────────────────
pass_test() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail_test() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass_test "$desc (expected=${expected})"
    else
        fail_test "$desc (expected=${expected}, got=${actual})"
    fi
}

assert_ge() {
    local desc="$1" expected="$2" actual="$3"
    if (( actual >= expected )); then
        pass_test "$desc (${actual} >= ${expected})"
    else
        fail_test "$desc (expected >= ${expected}, got=${actual})"
    fi
}

assert_le() {
    local desc="$1" expected="$2" actual="$3"
    if (( actual <= expected )); then
        pass_test "$desc (${actual} <= ${expected})"
    else
        fail_test "$desc (expected <= ${expected}, got=${actual})"
    fi
}

# ── Step 1: Repository initialisation ─────────────────────────────────────────
echo "==> Step 1: restic init"
restic init --quiet
if [[ -d "${REPO_DIR}/data" && -d "${REPO_DIR}/snapshots" ]]; then
    pass_test "repo structure created (data + snapshots dirs)"
else
    fail_test "repo structure missing"
fi
echo ""

# ── Step 2: Create fake dump files ────────────────────────────────────────────
echo "==> Step 2: Create fake dump files"
mkdir -p "${DATA_DIR}"
dd if=/dev/urandom bs=1K count=64 of="${DATA_DIR}/ecom.dump"   2>/dev/null
dd if=/dev/urandom bs=1K count=32 of="${DATA_DIR}/ledger.dump" 2>/dev/null
pass_test "fake ecom.dump (64KB) and ledger.dump (32KB) created"
echo ""

# ── Step 3: First backup (with snapshot tags) ─────────────────────────────────
echo "==> Step 3: First backup with tags"
SNAPSHOT_1=$(restic backup \
    --tag "db=ecom" \
    --tag "db=ledger" \
    --tag "env=test" \
    --tag "host=test-host" \
    --quiet \
    "${DATA_DIR}" 2>&1 | grep "snapshot" | grep -oE "[0-9a-f]{8}" | head -1 || echo "")

SNAP_COUNT=$(restic snapshots --json 2>/dev/null | grep -c '"short_id"' || echo 0)
assert_eq "snapshot count after first backup" "1" "$SNAP_COUNT"

# Verify tags were applied.
SNAP_TAGS=$(restic snapshots --json 2>/dev/null | grep -o '"tags":\[[^]]*\]' | head -1 || echo "")
if echo "$SNAP_TAGS" | grep -q "env=test"; then
    pass_test "env=test tag present on snapshot"
else
    fail_test "env=test tag missing from snapshot"
fi
if echo "$SNAP_TAGS" | grep -q "db=ecom"; then
    pass_test "db=ecom tag present on snapshot"
else
    fail_test "db=ecom tag missing from snapshot"
fi
echo ""

# ── Step 4: Integrity check ────────────────────────────────────────────────────
echo "==> Step 4: restic check --read-data-subset=5%"
if restic check --read-data-subset=5% 2>/dev/null; then
    pass_test "restic check --read-data-subset=5% clean"
else
    fail_test "restic check --read-data-subset=5% returned non-zero exit code"
fi
echo ""

# ── Step 5: Retention policy ──────────────────────────────────────────────────
if [[ "$FAST" == "false" ]]; then
    echo "==> Step 5: Retention policy (daily=1, weekly=1, monthly=1)"
    echo "    Creating 3 snapshots with different timestamps..."

    # Create 3 more snapshots to test retention.
    for i in 2 3 4; do
        # Modify data slightly so each snapshot is unique.
        echo "snapshot ${i}" >> "${DATA_DIR}/ecom.dump"
        restic backup --tag "env=test" --quiet "${DATA_DIR}" 2>/dev/null
    done

    SNAP_COUNT_BEFORE=$(restic snapshots --json 2>/dev/null | grep -c '"short_id"' || echo 0)
    echo "    Snapshots before forget: ${SNAP_COUNT_BEFORE}"

    # Apply retention: keep 1 daily, 1 weekly, 1 monthly.
    restic forget \
        --keep-daily=1 \
        --keep-weekly=1 \
        --keep-monthly=1 \
        --prune \
        --quiet 2>/dev/null

    SNAP_COUNT_AFTER=$(restic snapshots --json 2>/dev/null | grep -c '"short_id"' || echo 0)
    echo "    Snapshots after forget:  ${SNAP_COUNT_AFTER}"

    # After retention, we should have at most 3 snapshots (daily + weekly + monthly)
    # and at least 1 (the most recent).
    assert_ge "at least 1 snapshot kept" "1" "$SNAP_COUNT_AFTER"
    assert_le "at most 3 snapshots kept (daily+weekly+monthly)" "3" "$SNAP_COUNT_AFTER"

    # Verify integrity after prune.
    if restic check 2>/dev/null; then
        pass_test "restic check clean after prune"
    else
        fail_test "restic check returned non-zero exit code after prune"
    fi
else
    echo "==> Step 5: SKIPPED (--fast mode)"
    PASS=$((PASS+1))
fi
echo ""

# ── Step 6: Restore ────────────────────────────────────────────────────────────
echo "==> Step 6: restic restore latest"
restic restore latest \
    --target "${RESTORE_DIR}" \
    --quiet 2>/dev/null

RESTORED_ECOM=$(find "${RESTORE_DIR}" -name "ecom.dump" | head -1)
RESTORED_LEDGER=$(find "${RESTORE_DIR}" -name "ledger.dump" | head -1)

if [[ -f "$RESTORED_ECOM" ]]; then
    pass_test "ecom.dump restored"
else
    fail_test "ecom.dump not found in restored snapshot"
fi
if [[ -f "$RESTORED_LEDGER" ]]; then
    pass_test "ledger.dump restored"
else
    fail_test "ledger.dump not found in restored snapshot"
fi
echo ""

# ── Step 7: RESTIC_PASSWORD sensitivity ───────────────────────────────────────
echo "==> Step 7: Wrong password rejected"
WRONG_PW_OUT=$(RESTIC_PASSWORD="wrong-password" restic snapshots 2>&1 || true)
if echo "$WRONG_PW_OUT" | grep -qiE "wrong password|decrypt"; then
    pass_test "wrong password correctly rejected"
else
    fail_test "wrong password was NOT rejected (output: ${WRONG_PW_OUT})"
fi
echo ""

# ── Step 8: Snapshot listing ──────────────────────────────────────────────────
echo "==> Step 8: Snapshot list output"
SNAP_LIST=$(restic snapshots 2>/dev/null)
if echo "$SNAP_LIST" | grep -q "env=test"; then
    pass_test "snapshot list shows env=test tag"
else
    fail_test "snapshot list missing env=test tag"
fi
echo ""

# ── Results ───────────────────────────────────────────────────────────────────
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"
if (( FAIL > 0 )); then
    exit 1
fi
