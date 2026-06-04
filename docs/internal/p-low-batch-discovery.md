# Step 5 LOW Batch + HeroCarousel — Discovery & Triage

Per-finding re-verification at PR time (PR #60 protocol). Each finding triaged into
FIX / CORRECTED / NOT-ACTIONABLE / ESCALATE / DEFER. Branch `chore/step5-low-batch`.

## Outcome table

| Finding | Audit claim | On-branch verification | Outcome | Notes |
|---|---|---|---|---|
| **P-004** | card lacks favorites-count (LOW) | `product_card.dart` has a heart *toggle*, no count; `ProductSummary` (mopro_api) exposes no count field | **NOT-ACTIONABLE** | backend-gated — needs a `favorites_count` field on the product-summary response (same shape as P-008b's data-dark UI). The card UI is correct. |
| **P-009** | card lacks merch badges Kargo Bedava/campaign/bestseller | `ProductSummary` exposes no `free_shipping`/`campaign`/`badge` field; P-028 added the `free_shipping` *column* but not the response field, and it's unpopulated | **NOT-ACTIONABLE** | backend-gated. **The prompt mislabeled this LOW — the audit has it as MED.** A badge UI is pointless until the API exposes the flags + has data. |
| **P-011** | cart lacks promo-code entry (LOW) | the cart mounts `OrderSummaryCard` (`cart_screen.dart:120`), which **has** a coupon input (`order_summary_card.dart:97-109`, inert placeholder). The audit cited `cart_totals_summary.dart` — an **orphaned** widget the cart no longer uses. | **CORRECTED** | (a) "no promo field" is **wrong** — a coupon entry exists (placeholder; "coupon backend not wired"). (b) cross-sell + (c) saved-for-later remain absent (PARK/additive, per the audit). |
| **P-012** | checkout stepper vs single-page (LOW) | `checkout_stepper.dart` lives in `checkout/widgets/` (the audit's path was top-level; it exists) and renders a coherent multi-screen stepper; 3-DS / SAQ-A justify screen separation | **NOT-ACTIONABLE** | documented design — don't restructure a working stepper on taste (the audit's own recommendation). |
| **P-013** | favorites is a flat list (LOW) | `features/favorites/` = 2 files, flat grid; no collection model | **NOT-ACTIONABLE** | collections are a PARK product-intent decision; add/remove is at parity (heart on cards, guest-local + sync-on-auth). |
| **P-015** | PDP variant swatches / size-guide fidelity (LOW, PROBABLE) | `PdpVariantSelector` renders a `FilterChip` per variant but lets you select **out-of-stock** variants (`onSelected` is unconditional); `Variant.stock` is available (`variant.dart:120`) | **FIX** | disable + strike-through out-of-stock chips. A *confirmable Mopro-side* UX bug (selecting an OOS variant enables the CTA → add fails) — independent of the Trendyol 403, so actionable now. |
| **HeroCarousel** | orphaned widget (PR #82) | `git grep HeroCarousel\|hero_slides` (excl. their own files) = **zero consumers**; home (`home_screen.dart`) mounts `MoodStoriesStrip` → `_BannerCarousel` | **REMOVE** | delete `lib/features/catalog/widgets/hero_carousel.dart` + `lib/data/hero_slides.dart` + the `marketing.hero.*` block (8 keys; tr-TR + en-US — de-DE/ar-AE lack it). |

## Distribution: 1 FIX · 1 CORRECTED · 4 NOT-ACTIONABLE · 0 ESCALATE · 0 DEFER · HeroCarousel REMOVE

The "heavy-NOT-ACTIONABLE" arc outcome (prompt §11): the cleanup/tests/architecture work raised
the floor, so the LOW tail is mostly **backend-gated** (P-004, P-009), **intentional / documented
design** (P-011 — cashback-not-coupons; P-012 — the 3-DS stepper), or **PARK-pending-product-intent**
(P-013). One genuine FIX (P-015, OOS variants) and one factual CORRECTED (P-011, the coupon field).

## Secondary observations (logged, NOT actioned — anti-goal: no scope-creep cleanup)
- **Audit §3.2 narrative is inaccurate:** "home mounts hero carousel → MoodStoriesStrip" — home actually
  mounts `MoodStoriesStrip` → `_BannerCarousel` (no HeroCarousel). Corrected in the closure commit.
- `cart_totals_summary.dart` appears orphaned (cart uses `OrderSummaryCard`) — a cleanup nit; **not removed**
  here (scope is only the named HeroCarousel orphan). Flagged for a future cleanup sweep.
- empty `features/orders/` dir (audit §3.11) — same: out of scope, flagged.

## Backend follow-up that unblocks P-004 + P-009 (not filed as a NEW finding — folded into the existing P-008b/P-009 catalog-API note)
Both need the catalog `ProductSummary` response enriched: a `favorites_count` field (P-004) and
`free_shipping`/`campaign` flags (P-009 — the `free_shipping` column exists post-P-028 but isn't in the
response and is unpopulated). One "ProductSummary enrichment" backend PR would unblock P-004 + P-009 + the
dark P-008b discount/lowest-30d data together.
