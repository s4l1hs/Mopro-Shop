#!/usr/bin/env bash
# Section F — Data Integrity
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.

check_data() {
  local SEC="F"

  # F1: Reference categories = 42 (launch taxonomy, drives commission rules)
  local cats; cats=$(vds_int CATEGORIES_COUNT)
  if [[ "$cats" -eq 42 ]]; then
    pass "$SEC" "categories-count" "42 categories in ref_schema.categories"
  elif [[ "$cats" -gt 0 ]]; then
    fail "$SEC" "categories-count" "${cats} categories (want exactly 42) — reseed ref_schema"
  else
    fail "$SEC" "categories-count" "0 categories — migrations or seeds not applied"
  fi

  # F2: At least 1 product listed (WARN — needed for meaningful smoke test and first order)
  local prods; prods=$(vds_int PRODUCTS_COUNT)
  if [[ "$prods" -ge 1 ]]; then
    pass "$SEC" "products-seeded" "${prods} product(s) in catalog_schema.products"
  else
    warn "$SEC" "products-seeded" "0 products — buyers will see empty catalog at launch"
  fi

  # F3: At least 1 seller onboarded (WARN — needed to process any order)
  local sells; sells=$(vds_int SELLERS_COUNT)
  if [[ "$sells" -ge 1 ]]; then
    pass "$SEC" "sellers-onboarded" "${sells} seller(s) in seller_schema.sellers"
  else
    warn "$SEC" "sellers-onboarded" "0 sellers — no orders can be fulfilled at launch"
  fi
}
