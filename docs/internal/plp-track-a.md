# PLP Track A — confirmed polish batch — discovery + verdict

> Build only **CONFIRMED** items whose backing data exists; note the rest as
> data-gated. Verdict: **all three candidates are gated → no client-side polish
> ships this track.** (PROBABLE items skipped per the work order — they await the
> live walk.)

## PLP-09 — fast-delivery ("Hızlı Teslimat") — **DATA-GATED**

- `ProductSummary` has `freeShipping` but **no** fast-delivery / delivery-ETA
  field; **no** `fast_delivery` / `delivery_eta` column exists in `migrations/
  ecom/*`. The `listProducts` API accepts `freeShipping` but **no** fast-delivery
  param. There is no flag to surface as a badge or filter.
- **Verdict:** data-gated — needs a backend `fast_delivery` (or delivery-SLA)
  flag + API param first. Not built. Ledger note.

## PLP-16 — ranked bestseller badge ("Çok Satan N") — **BACKEND-SURFACING (DEFER)**

- The **rank data exists** — `analytics_schema.popular_products` (`0080`,
  `scope` + `view_count DESC`, indexed). But the catalog handler reads it from
  **analytics_schema** and passes the *ordered ID list* into the catalog query
  via `array_position` (`repository.go:427`) **for sort only** — it never attaches
  a rank *number* to each `ProductSummary`, and `ProductSummary` has only the
  unranked `isBestseller` bool.
- Surfacing "Çok Satan **N**" is a **full vertical**: handler attaches
  `rank = index+1` from the popular list it already fetches (app-merge, **§5-safe
  — no cross-schema JOIN**) → `ProductSummary.bestseller_rank` field → OpenAPI
  spec + Go/Dart codegen → ranked card badge. That's a feature, not "polish".
- **Verdict:** DEFER as a focused **"surface bestseller rank"** backend task
  (ledger). Data exists; surfacing is the work. Not crammed into the polish PR.

## PLP-17 — official-seller badge ("Resmi satıcı") — **DATA-GATED**

- No official / verified / certified **seller** flag exists (`internal/seller`,
  `migrations`); the "verified" columns are email/OTP auth, unrelated. The seller
  model has no official-status field.
- **Verdict:** data-gated — needs a seller `is_official` flag first. Not built.

## Skipped (PROBABLE — await Salih's live walk)

PLP-02 (mobile applied-chips), PLP-06 (quick pills), PLP-07 (brand counts,
softened/inconclusive), PLP-08 (no-results CTA), PLP-10 (header search) — all
PROBABLE/visual in the registry. Not in scope for a CONFIRMED-only batch.

## Outcome

No client-side code this track. Audit: PLP-09/16/17 annotated (gated/DEFER);
ledger records the two surfacing tasks (PLP-16 bestseller-rank, PLP-09
fast-delivery flag, PLP-17 official-seller flag — all backend-data prerequisites).
