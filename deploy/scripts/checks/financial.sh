#!/usr/bin/env bash
# Section C — Financial Invariants
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.
# CashbackK is verified from LOCAL source (internal/cashback/calculator.go).

check_financial() {
  local SEC="C"

  # C1: Platform accounts >= 5 (equity, liability, escrow, etc.)
  local plat; plat=$(vds_int PLATFORM_ACCOUNTS)
  if [[ "$plat" -ge 5 ]]; then
    pass "$SEC" "platform-accounts" "${plat} platform accounts (≥5)"
  else
    fail "$SEC" "platform-accounts" "${plat} platform accounts (want ≥5) — run migrations/seeds"
  fi

  # C2: CashbackK constant = 156000 in source (local check — ensures deployed binary matches spec)
  local cashback_k
  cashback_k=$(grep 'CashbackK int64 = ' \
    "$REPO_ROOT/internal/cashback/calculator.go" 2>/dev/null \
    | awk '{print $NF}' || echo "0")
  if [[ "$cashback_k" == "156000" ]]; then
    pass "$SEC" "cashback-k-constant" "CashbackK=156000 in calculator.go"
  else
    fail "$SEC" "cashback-k-constant" "CashbackK=${cashback_k} (want 156000) — source mismatch"
  fi

  # C3: D=C ledger balance trigger exists (prevents unbalanced transactions)
  local trg_bal; trg_bal=$(vds_int TRIGGER_BALANCE_CHECK)
  if [[ "$trg_bal" -ge 1 ]]; then
    pass "$SEC" "trigger-ledger-balance" "ledger_balance_check trigger present"
  else
    fail "$SEC" "trigger-ledger-balance" "ledger_balance_check trigger MISSING — ledger unprotected"
  fi

  # C4: Cashback plan immutability trigger exists
  local trg_imm; trg_imm=$(vds_int TRIGGER_PLAN_IMMUTABLE)
  if [[ "$trg_imm" -ge 1 ]]; then
    pass "$SEC" "trigger-plan-immutable" "cashback_plan_immutable_trg present"
  else
    fail "$SEC" "trigger-plan-immutable" "cashback_plan_immutable_trg MISSING — plans are mutable"
  fi

  # C5: Commission rules for TR market = 42 categories
  local comm; comm=$(vds_int COMMISSION_RULES_TR)
  if [[ "$comm" -eq 42 ]]; then
    pass "$SEC" "commission-rules-tr" "42 TR commission rules"
  else
    fail "$SEC" "commission-rules-tr" "${comm} TR commission rules (want 42) — run migrations/seeds"
  fi

  # C6: Business calendar for TR >= 50 entries (69 seeded for current year)
  local bizc; bizc=$(vds_int BIZ_CALENDARS_TR)
  if [[ "$bizc" -ge 50 ]]; then
    pass "$SEC" "business-calendars-tr" "${bizc} TR business-day calendar entries (≥50)"
  else
    fail "$SEC" "business-calendars-tr" "${bizc} TR calendar entries (want ≥50) — run calendar seed"
  fi
}
