# Trendyol Parity Audit — Orders (Siparişlerim)

> **Audit only — no code.** Self-audit of the Orders surface (history + detail) vs a
> **provisional** Trendyol baseline (§2), seeded for Salih's walk. IDs **OR-NN**,
> #09 walk format. Sibling of the Cart/Account/PDP/PLP/Search/Favorites audits.
> `src` = Mopro code fact; `walk` = Salih's observation. Auth-gated.
>
> **METHODOLOGY — read-path reality check** (the Account/Cart lesson): every section
> rated **L** live (real backend) · **S** stub (UI over no/dead backend) · **U**
> UI-only (client, no backend) · **A** absent (no UI + no backend = an honest gap,
> *not* a stub). **Result: the Orders core is LIVE with NO stubs** — the gaps are
> honest **A**bsences (tracking/address/invoice/reorder), distinct from the
> dead-button stubs found in Account (Help, Cards) and Cart.
>
> **Surface (source):** `order_history_screen` (list) · `order_detail_screen`
> (+ `OrderStatusTimeline`, `CashbackSchedule`, `order_eligibility_actions`,
> `cancel_order_dialog`, `refund_status_card`) · `order_summary_card` · returns
> (`returns_list_screen`/`order_return_flow_screen` — **own audit**). Providers:
> `ordersProvider`, `order_detail_provider`. DTOs: `OrderDto`, `OrderItemDto`,
> `OrderActions`, `RefundInfo`. Backend: `handleListOrders`/`handleGetOrder` →
> `order.Service` → `pgxOrderRepository` (postgres-ecom).

---

## §0 — Legend

- **Read-path** — **L** live · **S** stub · **U** UI-only · **A** absent (gap).
- **Confidence** — **CONFIRMED** (source) · **PROBABLE** (walk) · **MATCHED** ·
  **NOT-ACTIONABLE** (intentional divergence).

---

## §1 — Summary

- **The Orders core is LIVE** — `GET /orders` + `GET /orders/{id}` are real
  (`handleListOrders`/`handleGetOrder` → `order.Service.ListOrders/GetOrder` →
  `pgxOrderRepository`), serving status, the totals breakdown
  (items/shipping/commission/kdv), items, the status dates, `actions`
  (canCancel/canReturn), and `refund`. List + detail + status timeline + cancel +
  return + cashback schedule all read a real backend.
- **NO stubs** — the read-path check found **no UI-over-dead-backend** in Orders
  (unlike Account's Help/Cards). That's the headline: the surface is honest.
- **Absent features (A) — CONFIRMED gaps, not stubs:** **OR-01** cargo tracking
  (carrier + tracking no.), **OR-02** delivery address on the order, **OR-03**
  invoice / e-arşiv, **OR-04** reorder, **OR-05** variant label on order-item lines,
  **OR-06** server-side order search/pagination (list loads all + filters
  client-side).
- **NOT-ACTIONABLE: 3** — the cashback-schedule on the order + refund-as-coin
  (`wallet_credit`) (Mopro model), brand-orange tokens.

---

## §2 — Self-audit (Mopro current vs baseline) — with read-path

### Order list (`order_history_screen`)

| Feature | Trendyol | Mopro (`src`) | Read-path | Status | Sev |
|---|---|---|---|---|---|
| Orders by date + status badge + total + thumbnails | yes | list of `OrderDto` (`OrderStatusChip`, total, item thumbs) | **L** (`GET /orders`) | **MATCHED** | — |
| Filter | by status | `_OrderFilter {all, active, completed, cancelled}` — **client-side** over the loaded list | **U** (client) | **MATCHED** (Mopro-internal) | — |
| Search | order/product search | `_searchCtrl` — **client-side** over loaded orders | **U** (client) | **OR-06** no *server* search | LOW |
| Pagination | paged | `ListOrders(userID)` returns **all** (no `page`/`limit`) | **A** | **OR-06** no server pagination (scale) | LOW |
| Per-order quick action: detail | yes | tap → detail | **L** | **MATCHED** | — |
| Per-order quick action: return | yes | via `actions.canReturn` | **L** | **MATCHED** (returns = own audit) | — |
| Per-order quick action: reorder | "Tekrar sipariş ver" | reorder on the **detail** (re-add items → cart) | **L** | **OR-04 ✅ RESOLVED** (detail-level; list quick-action still A) | — |
| Per-order quick action: track | "Kargo takip" | — | **A** | **OR-01** no tracking | MED |

### Order detail (`order_detail_screen`)

| Feature | Trendyol | Mopro (`src`) | Read-path | Status | Sev |
|---|---|---|---|---|---|
| Line items (image/title/qty/price) | yes | `OrderItemDto` (title/price/qty/cover) | **L** | **MATCHED** | — |
| Line-item **variant label** | colour/size | `OrderItemDto` has `variantId` only (no label) | **A** | **OR-05** no variant label (the pre-enrichment cart gap; same `GetVariantByID` carrier fixes it) | LOW–MED |
| **Status timeline** | order states | `OrderStatusTimeline(status)` from status + `shipped_at`/`delivered_at` | **L** (derived) | **MATCHED** (simpler than carrier tracking) | — |
| **Cargo tracking** (carrier + tracking no. + live status) | yes | carriers push via `POST /shipping/webhook/*` but **not surfaced**; `OrderDto` has no carrier/tracking_no | **A** | **OR-01** no consumer tracking | MED |
| **Delivery address** | yes | `OrderDto` carries **no address** | **A** | **OR-02** no delivery address on the order | MED |
| Payment summary (subtotal/shipping/KDV/total) | yes | `items/shipping/commission/kdv/total` minor on `OrderDto` | **L** | **MATCHED** | — |
| Discounts on the order | coupon/basket-disc | — (the cart discount cluster isn't built) | **A** | ties Cart **CT-09** | LOW |
| Cashback schedule | (n/a) | `CashbackSchedule` (monthly coin plan) | **L** | **NOT-ACTIONABLE** (Mopro PLUS) | — |
| **Invoice / e-arşiv** | PDF / e-arşiv link | — (`internal/einvoice` is **PLANNED**, not built) | **A** | **OR-03** no invoice (TR legal: e-arşiv) | MED |
| Cancel / return entry | yes | `order_eligibility_actions` + `POST /orders/{id}/cancel`,`/returns` | **L** | **MATCHED** | — |
| Refund status | yes | `RefundInfo` (`refund_status_card`) + `/orders/{id}/refund` | **L** | **MATCHED** (refund-as-coin = NOT-ACTIONABLE) | — |
| Reorder | "Tekrar sipariş" | `_ReorderButton` → re-add items to cart (graceful OOS) | **L** | **OR-04 ✅ RESOLVED** (`feat/quick-functional-gaps`) | — |
| Per-item help / Q&A | yes | — | **A** | **OR-07** no per-order help/Q&A entry | LOW |

---

## §3 — The read-path check, distilled

> **Orders is the clean case.** Every "matched" above is verified to a real backend
> (handler → `order.Service` → `pgxOrderRepository`, or the fin cashback plan) — the
> list, detail, status, totals, cancel, return, and refund all read live data. The
> read-path check found **zero stubs** here (contrast Account: Help/Cards dead
> buttons; Cart: the whole read-path). The Orders gaps are **honest A-absences** —
> features not built (tracking, address, invoice, reorder, variant-label,
> server-search) — which is a *different* (and healthier) finding class than a stub.
> Cheapest wins: **OR-05** (variant label — the cart's `GetVariantByID` enrichment
> carrier already exists) and **OR-04** (reorder — re-add the order's items to cart).

---

## §4 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — Cashback schedule on the order** (the monthly-coin plan) — a Mopro PLUS,
  not a Trendyol parity item.
- **D2 — Refund-as-coin** (`RefundInfo.method = wallet_credit`) alongside
  original-payment — the perpetual-cashback model.
- **D3 — Brand-orange tokens.**

---

## §5 — Walk slots (Salih, logged-in)

1. **List** — orders by date, status chips, totals, thumbnails; the client filter
   tabs (all/active/completed/cancelled) + search box.
2. **Detail** — items, status timeline, totals breakdown, cashback schedule, the
   cancel/return actions, refund status.
3. **OR-01** — confirm there's **no carrier/tracking-number** "where's my package".
4. **OR-02** — confirm the detail shows **no delivery address**.
5. **OR-03** — confirm **no invoice / e-arşiv** link.
6. **OR-04 / OR-05** — confirm **no reorder** + **no variant label** on item lines.
7. **OR-06** — confirm the list isn't server-paged/searched (client-only).

---

## §6 — Prioritized fix list (after the walk)

> No stubs to wire (unlike Account). These are **build-the-absent-feature** items:

1. **OR-01 cargo tracking** + **OR-02 delivery address** — the highest-value detail
   gaps (the webhook ingest exists for OR-01; surface carrier + tracking_no + the
   address snapshot on the order).
2. **OR-03 invoice / e-arşiv** — TR legal; gated on `internal/einvoice` (PLANNED).
3. **OR-05 variant label** (cheap — reuse the cart `GetVariantByID` enrichment) +
   **OR-04 reorder** (re-add items to cart).
4. **OR-06** server search/pagination (scale) · **OR-07** per-order help/Q&A.

> **Status: SEEDED — awaiting Salih's walk.** Read-path **L/A** ratings are CONFIRMED
> from source; Trendyol-side deltas firm up on the walk.
