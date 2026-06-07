# GOLD-REGEN — Prediction Doc (commit 1, before any regen)

> Predict-then-verify (discipline #82) for the Linux golden regen covering drift since the last
> rebaseline. Written BEFORE dispatching `golden-rebaseline.yml`; §4 reconciles after.

## 1. Premise corrections (source over prompt)

- **"Last golden regen was PR #98" is wrong.** #98 is `chore: trigger CI after repo visibility
  change` (no goldens). Regens are the workflow's auto-commits; the latest in main is
  `7e1f0a4b` (2026-06-04 14:05 UTC); the latest touching the **PDP/catalog-widget** goldens is
  `e050d0b7` (2026-06-03).
- Candidate drift PRs merged after that: #97 (06-06), #99 (06-06), #100 (06-06), #102 (06-06),
  #103 (06-06) — per the prompt's window plus #97, which actually shipped the only new PDP widget.

## 2. Per-PR visual-impact analysis

| PR | mobile/lib diff | Visual impact on golden-covered widgets |
|---|---|---|
| #97 delivery-ETA | `product_detail_screen.dart` + **new** `pdp_delivery_info.dart` | Screen inserts `PdpDeliveryInfo` **only when `product.deliveryEta != null`** (screen lines 470/608). Both PDP golden fixtures (`_variantsProduct`/`_simpleProduct` in `pdp_goldens_test.dart`) **omit `deliveryEta`** → nothing rendered → no pixels. |
| #99 categoryId on product_view | `product_detail_screen.dart` | Analytics event payload only — no widget/pixel change. |
| #100 per-category bestseller | *(no mobile/lib files)* | Backend + handler only. |
| #102 PDP strikethrough | `product_detail_screen.dart`, `pdp_price_block.dart`, `mopro_api` Variant model | `PdpPriceBlock._hasDiscount` requires `originalPriceMinor != null && > priceMinor`; golden fixtures' variants **omit `originalPriceMinor`/`lowestIn30DaysMinor`** → strikethrough/pill/hint branches never render. (#102's session recorded "0 golden flips" for the same reason — the #94-class "fixture doesn't carry the value".) |
| #103 verify wiring | *(no mobile files)* | CI-only. |

## 3. Predicted changed-set: **∅ (zero goldens flip)**

Independent corroboration: none of #97–#103 shipped a single `goldens/*.png`, yet `flutter-ci`
(ubuntu-latest, runs every golden comparison) has been **green on main** continuously since the
06-03/06-04 regens. If any committed baseline mismatched current rendering, main would be red.
The committed baselines therefore already equal current Linux rendering, and a regen should
produce the workflow's "No golden changes to commit." path.

**What a non-empty changed-set would mean (escape hatches, pre-declared):**
- *Any PDP golden flips* → an unguarded render path in #97/#102 that CI somehow tolerates —
  investigate before merging (likely impossible given green CI, listed for completeness).
- *A broad many-file flip across unrelated surfaces* → **runner environment drift** (ubuntu-latest
  image/font/Flutter `3.x` patch bump since 06-04), not PR drift — assess whether to adopt the new
  environment baseline as its own decision, NOT silently merge.
- *`recs_pdp_similar_*` or rail goldens flipping* → same env-drift class (no code touched them).

## 4. Reconciliation (filled after the workflow run)

- Dispatched: `golden-rebaseline.yml` run **27102117580** on this branch (ubuntu-latest),
  2026-06-07 19:17 UTC — concluded **success**.
- Actual changed-set: **none** — the workflow regenerated all goldens with `--update-goldens`
  and reported **"No golden changes to commit."** (no auto-commit pushed).
- Verdict vs prediction: **exact match — predicted ∅, actual ∅.** No unexpected flips (no env
  drift on the runner since the 06-03/06-04 baselines), and both predicted-but-unflipped
  candidates behaved per §2 (fixtures don't carry `deliveryEta`/`originalPriceMinor` — the
  #94-class case, documented, not forced per §7-5). The committed Linux baselines are confirmed
  in sync with post-#103 widget state; the Path-B Home/PDP PR starts from an unambiguous baseline.

## 5. Documented residual (NOT this PR)

The real gap behind the "PDP goldens" follow-up note is **coverage, not drift**: `PdpDeliveryInfo`
and the #102 strikethrough state have **no golden exercising them** (fixtures deliberately omit the
values). Adding a fixture variant that carries `deliveryEta` + `originalPriceMinor` belongs to the
first Path-B PDP/Home surface PR (it changes what the goldens assert — out of this PR's
rebaseline-only scope per §0/§7-3).
