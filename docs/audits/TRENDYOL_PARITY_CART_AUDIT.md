# Trendyol Parity Audit — Cart

> **Audit only — no code.** Self-audit of the Cart surface vs a **provisional**
> Trendyol baseline (§2), seeded for Salih's walk. IDs **CT-NN**, #09 walk format.
> `src` = Mopro code fact; `walk` = Salih's visual/interaction observation. Cart is
> **guest-accessible**; **checkout is auth-gated** (Mopro gates cart→checkout).
> Cart sets the line-item + price-summary patterns **Checkout** inherits — so this
> is thorough on those.
>
> **Surface (source):** `CartScreen` (mobile list / desktop two-column pinned
> summary) · `CartLineCard` · `CartTotalsSummary` (mobile) / `OrderSummaryCard`
> (desktop) · `EmptyCart` · `cartProvider` + `guestCartProvider` +
> `cartMergeService` + `cartMonthlyCashbackProvider`. DTOs: `CartDto`
> (`lines`, `totalsBySeller`, `grandTotalMinor`, `kdvIncludedMinor`,
> `isAboveTotalLimit`), `CartLineDto`, `SellerTotalDto` (`itemsMinor`,
> `shippingMinor`, `totalMinor`).

---

## §0 — Legend

- **Source** — `src` (code fact) · `walk` (Salih, visual/interaction).
- **Confidence** — **CONFIRMED** (structural source fact) · **PROBABLE**
  (visual/interaction — awaits walk) · **MATCHED** (parity, verified) ·
  **NOT-ACTIONABLE** (intentional divergence).

---

## §1 — Summary

> ### ✅ RESOLVED (2026-06-10, `feat/cart-readpath-enrichment` PR 1) — the cart read-path is now enriched
> ~~The cart read-path was a backend STUB: `GET /cart` returned raw
> `{user_id, items:[{variant_id, qty}]}` → the authed cart rendered empty.~~
> **Fixed:** `handleGetCart` now enriches §5-safely (`enrichCart`) — `GetVariantByID`
> (label/price/seller_id/product_id/image) + `ListProductsByIDs` (title/cover) +
> the new `seller.SellerNamesByIDs` carrier (name) + `GetCommissionForCategory`
> (KDV) — and emits the full `CartDto`: `lines` (incl. `seller_name` +
> `variant_label`), `totals_by_seller`, `grand_total_minor`, `kdv_included_minor`.
> The merge lives in `cmd/core-svc` (`internal/cart` imports neither catalog nor
> seller → no JOIN). **The authed cart + the checkout review (which reads the same
> `cart.lines`) now render → CT-01 / CT-04 / CT-05 + CHK-01 / CHK-02 closed.** The
> guest path is untouched. Discovery: `docs/internal/cart-readpath.md`. *(Still
> open: CT-02 free-shipping progress + CT-09 basket-discount — PR 2.)*

- **Cart is well-built (UI):** per-seller grouping, qty stepper, swipe+button remove,
  desktop price summary (subtotal/shipping/cashback/total + KDV-included), coin
  cashback line, auth-gated checkout CTA, empty state, clear-all, **guest cart +
  guest→auth merge**, stock reservation (`reservedUntil`) — *all built UI-side,
  awaiting the backend enrichment above.*
- **CONFIRMED gaps (src): 10** — CT-01 seller group shows `#id` not name + no
  per-seller subtotal; CT-02 no free-shipping progress; CT-03 coupon is a
  desktop-only placeholder (no backend); CT-04 mobile summary lacks the
  subtotal/shipping breakdown; CT-05 no variant label / save-for-later /
  move-to-favorites on a line; CT-06 no stock/price-changed warnings; CT-07/08 no
  recommendations (empty + populated); CT-09 no basket-discount line; CT-10
  "remove" has no real Undo action.
- **NOT-ACTIONABLE: 4** — coin/cashback line, brand tokens, the cart total-limit
  guardrail (`isAboveTotalLimit`), checkout auth-gating.
- **Seed/gating (§6):** cart is **populatable locally** (guest cart persists to
  SharedPreferences; add-to-cart from the PDP). Checkout is auth-gated.

---

## §2 — Self-audit (Mopro current vs baseline)

| ID | Baseline (Trendyol) | Mopro current (`src`) | Delta | Status | Sev |
|---|---|---|---|---|---|
| — | Line: image, title, variant, unit price, qty stepper, remove, **save-for-later/move-to-fav** | `CartLineCard` (now with **variant label**) + move-to-favorites | **CT-05 ✅ RESOLVED** — enriched `GET /cart` serves `variant_label` (colour/size) → rendered on the line; **save-for-later** (no saved list) separate | **CT-05 RESOLVED** | MED |
| — | Per-seller grouping w/ per-seller subtotal + cargo | `_SellerGroupHeader`: **seller name** + per-seller subtotal | **CT-01 ✅ RESOLVED** — enriched `GET /cart` serves `seller_name` + `totals_by_seller`; header shows the real name (fallback `#id`) + subtotal | **CT-01 RESOLVED** | MED |
| — | Summary: subtotal, cargo, coupon, "Sepette indirim", coin, **total** | desktop `OrderSummaryCard`; mobile `CartTotalsSummary` | **CT-04 ✅ RESOLVED**; **CT-09 DEFER (financial)** — `basket_discount_pct` is a **display-only card pill** (#133), **not applied to any price/total**; a real discount line needs it applied across pricing→order→payment→cashback (a money change, not display) → deferred to that pricing PR | **CT-04 RESOLVED / CT-09 DEFER** | MED |
| — | Coupon/promo field | desktop coupon `TextField` — **placeholder, no coupon backend** ("Coupon application is a placeholder"); mobile has none | non-functional + desktop-only | **CT-03** | MED |
| — | Free-shipping progress ("X TL daha ekle") | cart shipping is **unconditionally `0`** ("Ücretsiz"; cargo handled separately, §2.3/§4.8) | **CT-02 NOT-ACTIONABLE** — no cart-level shipping cost → **no threshold to progress toward**; fabricating one contradicts the always-free model | **NOT-ACTIONABLE** | — |
| — | Sticky checkout CTA with total | `CartTotalsSummary`/`OrderSummaryCard` checkout button → `requireAuth` → `/checkout` | — (**auth-gated**, intentional) | **MATCHED** | — |
| — | Empty cart + suggestions | `EmptyCart`: icon + title + subtitle + one CTA | **no recommendations/popular** | **CT-07** | LOW |
| — | Warnings: out/low-stock, price-changed-since-added | `isAboveTotalLimit` total cap only; `reservedUntil` held but not surfaced | **no stock / price-change warnings** on lines | **CT-06** | MED |
| — | Recommendations rail in cart | — | **absent** | **CT-08** | LOW |
| — | Remove → **Undo** | `_removeWithUndo` + a **real Undo `SnackBarAction`** (re-adds via `addItem`) | **CT-10 ✅ RESOLVED** | **CT-10 RESOLVED** | LOW–MED |

---

## §3 — Already-matched (VERIFIED from source)

Per-seller **grouping** (structure) · qty stepper (±, `updateQty`) · remove (swipe
`Dismissible` + button) · clear-all (+ confirm dialog) · desktop price summary
(subtotal + shipping[free@0] + cashback + **total**, KDV-included) · **coin
cashback** line (`cartMonthlyCashbackProvider`) · checkout CTA (**auth-gated**) ·
empty state · **guest cart** (SharedPreferences) + **guest→auth merge**
(`cartMergeService`) · desktop pinned summary column · **stock reservation**
(`reservedUntil`) · pull-to-refresh.

---

## §4 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — Coin/cashback line** in the summary (perpetual-cashback model).
- **D2 — Brand-orange tokens.**
- **D3 — Cart total-limit guardrail** (`isAboveTotalLimit` → `warning_total_limit`)
  — a Mopro risk cap, not a Trendyol parity gap.
- **D4 — Checkout auth-gating** (guest can build a cart; `requireAuth` gates
  `/checkout`) — intentional Mopro flow.

---

## §5 — Cascade to Checkout (§10)

The line-item + price-summary model here **is** the Checkout foundation:
`totalsBySeller` (per-seller items/shipping/total) + `grandTotalMinor` +
`kdvIncludedMinor` + the cashback line. Fixing CT-01 (seller name + per-seller
subtotal) and CT-04 (full mobile breakdown) here pays forward directly to
Checkout's order summary. The coupon (CT-03) + basket-discount (CT-09) gaps are
shared backend prerequisites for both surfaces.

---

## §6 — Seed / gating

- **Populatable locally:** the **guest cart** persists to SharedPreferences
  (`mopro_guest_cart`); add-to-cart from the PDP populates it pre-auth → the walk
  can build a cart without login. Auth users get the server cart + the **merge**
  on login.
- **Gating boundary:** cart **view/build = guest-OK**; **checkout = auth-gated**
  (`requireAuth` → `LoginRequiredSheet`). Note the per-seller grouping needs items
  from ≥2 sellers to walk fully (seed has multiple sellers — achievable).
- Caveat (from the PDP audit): 1 variant/product → the variant-label gap (CT-05)
  can't be walked richly, but it's a data-gated finding regardless.

---

## §7 — Walk-findings slots (Salih; #09 format)

> Walk: line card (variant, save-for-later), per-seller subtotals, the summary
> (mobile vs desktop breakdown, coupon, free-ship progress), warnings, empty +
> populated recommendations. New items continue at **CT-11+**.

```
### CT-NN — <one-line title>
- **Surface/region:** Cart › <line | seller group | summary | coupon | empty | warnings | recommendations>
- **Trendyol (live):** <observation>  [walk date: ____]
- **Mopro (current):** <file:line if known>
- **Delta / Status / Severity / Notes>
```

<!-- CT-01 — confirm Trendyol shows seller name + per-seller subtotal/cargo. -->
<!-- CT-02 — free-shipping progress bar wording/threshold. -->
<!-- CT-06 — stock + price-changed warning treatment. -->
<!-- CT-11 … -->

---

## §8 — Prioritized fix list (after the walk)

> **PREREQUISITE (discovered 2026-06-10):** CT-01/CT-04/CT-05 are **not** "cheap"
> and the data is **not** already in `totalsBySeller` — the backend serves none of
> the enriched cart response. They all sit behind **one backend lane: the cart
> read-path enrichment** (`GET /cart` → rich `CartDto` incl. lines w/
> seller_name + variant_label + `totals_by_seller` + `grand_total`). §5-safe via
> catalog + a new seller-name batch carrier; hand-written (cart isn't in the spec)
> + a live-handler contract test. Spec'd in `docs/internal/cart-line-metadata.md`.

1. **Cart read-path enrichment (NEW, prerequisite)** — build the enriched
   `GET /cart`. Unblocks CT-01 (seller name + subtotal), CT-04 (mobile breakdown),
   CT-05 (variant label). Necessarily includes the totals cluster.
2. **CT-05 extras** — save-for-later / move-to-favorites (move-to-fav UI shipped;
   save-for-later needs a saved-items store, separate).
3. **CT-06** — stock (out/low) + price-changed-since-added warnings (surface
   `reservedUntil`; add price-at-add).
4. **CT-02 / CT-09 / CT-03** — free-shipping progress; basket-discount line;
   coupon backend (shared with Checkout). Backend-gated.
5. **CT-07 / CT-08 / CT-10** — recommendations (empty + cart) + a real Undo. LOW.

> Severities provisional until the walk. No fixes in this PR.
