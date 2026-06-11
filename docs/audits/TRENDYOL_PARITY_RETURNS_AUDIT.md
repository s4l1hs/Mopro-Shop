# Trendyol Parity Audit — Returns (İadelerim / İade Talebi)

> **Audit only — no code.** Self-audit of the Returns surface (eligibility →
> request → status → refund → history) vs a **provisional** Trendyol baseline (§2),
> seeded for Salih's walk. IDs **RT-NN**, #09 walk format. **The last surface audit**
> — sibling of Cart/Account/Orders/PDP/PLP/Search/Favorites/Checkout. `src` = Mopro
> code fact; `walk` = Salih's observation. Auth-gated (every endpoint `requireAuth`).
>
> **METHODOLOGY — read-path reality check** (the Account/Cart lesson): every section
> rated **L** live (real backend) · **S** stub (UI over no/dead backend) · **U**
> UI-only (client, no backend) · **A** absent (no UI + no backend = an honest gap,
> *not* a stub). **Result: the Returns request/history/eligibility core is LIVE; the
> notable finding is RT-01 — the refund *settlement* of a return is not wired (the
> lifecycle can't reach `refunded`), so the refund card is a status that can't
> progress.** The rest are honest **A**-absences (return shipping/cargo-code, photos,
> the status-history audit trail not surfaced).
>
> **Surface (source):** `returns_list_screen` (İadelerim) · `order_return_flow_screen`
> (4-step: items → reasons → review → confirm) · `return_detail_screen`
> (+ `OrderStatusTimeline`, `RefundStatusCard`, `return_status_chip`). Providers:
> `returnsProvider`/`returnDetailProvider`, `return_flow_provider`. DTOs:
> `ReturnListItemDto`, `ReturnDetailDto`, `ReturnItemDto`, `CreateReturnRequest`,
> `ReturnReason`, `ReturnLifecycle`. Entry point: `order_eligibility_actions`
> (`order_detail_screen`, gated on `actions.canReturn` → `/orders/{id}/return`).
> Backend: `handleCreateReturn`/`handleListReturns`/`handleGetReturn` →
> `order.ReturnService` → `pgxReturnRepository` (postgres-ecom, `order_schema`).
> Seller side (drives status): `GET/POST /seller/returns/{id}/approve|reject`.

---

## §0 — Legend

- **Read-path** — **L** live · **S** stub · **U** UI-only · **A** absent (gap).
- **Confidence** — **CONFIRMED** (source) · **PROBABLE** (walk) · **MATCHED** ·
  **NOT-ACTIONABLE** (intentional divergence).

---

## §1 — Summary

- **The Returns request/history/eligibility core is LIVE** — eligibility is
  server-computed (`ReturnService.ComputeActions` → `OrderActions{canReturn,
  returnableUntil, returnableItems}` on the order DTO; 14-day window from
  `delivered_at`); the 4-step request flow posts to a real `POST /orders/{id}/returns`
  (`CreateReturn` → validate window/ownership/quantity → insert return + items +
  status-history in one tx); the list (`GET /returns`) and detail (`GET /returns/{id}`)
  read `pgxReturnRepository`. Seller approve/reject (`/seller/returns/...`) is a real
  backend that transitions `pending → approved|rejected`.
- **RT-01 — refund settlement (the headline) ✅ RESOLVED** (`feat/refund-settlement`).
  `SellerApprove` now settles in one tx: pending→approved→**refunded** + emits
  `ecom.return.refunded.v1` (order_schema.outbox, §4.5); fin-svc `internal/refund`
  consumes it and **mints the refund as Mopro Coin** (D `equity:refund_distribution`
  ↔ C the buyer wallet, migration 0082), idempotent on `refund:<return_id>`. The
  refund card now reaches "issued" with `method=wallet_credit`. Refund amount = the
  charged snapshot (`RefundAmountMinor`, CT-09+coupon-correct, partial-safe). No §12
  change (a new equity account within §4, the cashback_distribution pattern). Doc:
  `docs/internal/refund-settlement.md`.
- **Absent features (A) — CONFIRMED gaps, not stubs:** **RT-02** no return shipping
  (no cargo code / drop-off / return label / method selection — the confirm screen's
  "tracking_no" is just the return *id*); **RT-03** no return photos (damage evidence);
  **RT-04** the `return_status_history` table is written but **not surfaced** — the
  detail timeline is *derived from the current status* (4-state map), not the audit
  trail.
- **RT-06 — consumer status filter ✅ RESOLVED** (`feat/returns-ui-polish`). A
  client-side status chip bar on the return-history list (`returnsStatusFilterProvider`
  over the already-fetched list — no backend, no extra fetch). "All" + one chip per
  status present; hidden when only one status exists (single-status golden stays
  pixel-stable). Read-path confirmed: the list DTO already carries `status`.
- **Fidelity loss (U):** **RT-05** the flow collects a **per-item** reason + note but
  the contract takes a single return-level reason → it submits the *first* item's
  reason and folds notes into `description` (`buildRequest`). **DEFER (read-path
  confirmed):** surfacing per-item reasons in the detail needs a response field that
  does not exist — `order_schema.return_items` (migration 0070) and the `ReturnItem`
  struct carry only `order_item_id`+`quantity`; the reason lives on the return header.
  Rendering per-line reasons therefore requires a migration + `CreateReturn`/`GetReturn`
  change + an OpenAPI/codegen change (`reasons[] per line`). Out of scope for the
  no-codegen returns-UI lane (kept parallel-safe with OR-02); re-scoped as a contract
  change alongside RT-02/RT-03. See `docs/internal/returns-ui.md`.
- **NOT-ACTIONABLE: 3** — refund-as-coin (the `wallet_credit` model; the flow even
  previews `method_wallet` from `order.refund.isWallet`), the status-derived timeline
  (simpler than carrier tracking, same as Orders), brand-orange tokens.

---

## §2 — Self-audit (Mopro current vs baseline) — with read-path

### Eligibility (`order_eligibility_actions` → `ComputeActions`)

| Feature | Trendyol | Mopro (`src`) | Read-path | Status | Sev |
|---|---|---|---|---|---|
| Which orders/items are returnable | delivered + per-item | `ComputeActions`: `canReturn` iff `delivered` + within window + ≥1 item with remaining qty; `returnableItems[{itemId,maxQty}]` | **L** (server-computed on `OrderDto.actions`) | **MATCHED** | — |
| Return window | ~14–15 gün | `ReturnWindowDays = 14` from `delivered_at`; `returnableUntil` surfaced | **L** | **MATCHED** | — |
| Already-returned accounting | yes | `ReturnedQtyByOrder` subtracts prior returns from `maxQty` | **L** | **MATCHED** | — |
| Entry point | from order detail | `order_eligibility_actions` button (gated on `canReturn`) → `/orders/{id}/return` | **L** | **MATCHED** | — |

### Return request (`order_return_flow_screen`, 4 steps)

| Feature | Trendyol | Mopro (`src`) | Read-path | Status | Sev |
|---|---|---|---|---|---|
| Select item(s) + quantity | yes | step 1: per-item checkbox + qty stepper bounded by `maxQty`; default-all-remaining server-side | **L** (`POST /orders/{id}/returns`) | **MATCHED** | — |
| Reason | per-item reason dropdown | enum `wrong_product/not_as_described/damaged/size_issue/changed_mind/other`; UI is **per-item** | **L** (enum) / **U** (collapse) | **RT-05** per-item reason UI but single-reason contract (first item's reason; notes → description) | LOW |
| Free-text note | yes | per-item note (`other` shows a 200-char field); folded into `description` | **U** | **RT-05** (folded) | LOW |
| **Return method** (cargo code / drop-off / QR) | İade kargo kodu / drop-off | — (no method step; no cargo code/label; confirm shows the return *id* as "tracking_no") | **A** | **RT-02** no return shipping/cargo code | **MED** |
| **Photos** (damage evidence) | yes | — (request = reason + description + items only; no upload) | **A** | **RT-03** no return photos | MED |
| Refund preview | amount + method | step 3: client-side `refundEstimate` (Σ price×qty) + method preview (`method_wallet`/`method_original` from `order.refund.isWallet`) | **L/U** | **MATCHED** (refund-as-coin NOT-ACTIONABLE) | — |
| Idempotent submit | yes | `requireIdempotencyKey` on `POST /returns` | **L** | **MATCHED** | — |

### Status tracking (`return_detail_screen`)

| Feature | Trendyol | Mopro (`src`) | Read-path | Status | Sev |
|---|---|---|---|---|---|
| Return states | requested → approved → cargo → refunded | `pending/approved/rejected/refunded`; detail maps current status → a 4-state `OrderStatusTimeline` | **L** (derived) | **MATCHED** (derived, like Orders) | — |
| **Status-history timeline** | step-by-step with dates | `GET /returns/{id}` now returns `history[]` (`ListReturnStatusHistory`); detail renders the real event timeline (falls back to derived when empty) | **L** | **RT-04 ✅ RESOLVED** (`feat/quick-functional-gaps`) | — |
| Cargo/return-leg tracking | "kargoya verildi" + tracking | — (no return-shipment state at all; ties RT-02) | **A** | **RT-02** | MED |
| Refunded state reachable | yes | `SellerApprove` now settles pending→approved→**refunded** atomically | **L** | **RT-01 ✅ RESOLVED** (`feat/refund-settlement`) | — |

### Refund (`RefundStatusCard` / `buildReturnRefundView`)

| Feature | Trendyol | Mopro (`src`) | Read-path | Status | Sev |
|---|---|---|---|---|---|
| Refund amount | order/line total | `RefundAmountMinor` snapshotted at creation (`Σ unit_price×qty`) | **L** | **MATCHED** | — |
| Refund method | original payment | `buildReturnRefundView.method = wallet_credit` (refund-as-coin); mobile `RefundInfo.isWallet` → `returns.method_wallet` | **L** (display) | **NOT-ACTIONABLE** (refund-as-coin model — do not flag) | — |
| Refund **settlement** (status → issued + money moved) | auto on approval/receipt | **RT-01 ✅ RESOLVED**: `SellerApprove` settles in one tx (pending→approved→refunded) + emits `ecom.return.refunded.v1`; fin-svc `internal/refund` mints the refund as coin (D `equity:refund_distribution` ↔ C user wallet, idempotent `refund:<id>`). Card → "issued". | **L** | **RT-01 RESOLVED** (`feat/refund-settlement`) | — |
| Refund timing/estimate | "X iş günü" | `refundEstimateDays = 10` (display-only `estimatedAt`) | **L** (display) | **MATCHED** | — |

### Return history (`returns_list_screen` — İadelerim)

| Feature | Trendyol | Mopro (`src`) | Read-path | Status | Sev |
|---|---|---|---|---|---|
| Past returns + status | yes | `GET /returns` → `ReturnListItemDto` (id, order, status chip, reason, refund amount, date) | **L** | **MATCHED** | — |
| Empty state | yes | `returns.empty` + "go to orders" CTA | **L** | **MATCHED** | — |
| Pagination | paged | `limit/offset` + `hasMore` (`limit+1` probe) | **L** | **MATCHED** | — |
| Filter by status | yes | client-side status chip bar over the already-fetched list (`returnsStatusFilterProvider`); "All" + one chip per present status; hidden when single-status | **L** | **RT-06 ✅ RESOLVED** (`feat/returns-ui-polish`) | — |

---

## §3 — The read-path check, distilled

> **Returns is mostly the clean case — with one dead settlement step.** Eligibility,
> the 4-step request, the list, and the detail all verify to a real backend
> (`handler → order.ReturnService → pgxReturnRepository`, with seller approve/reject
> driving status). The check's payoff is **RT-01**: a UI-only pass would mark "refund
> ✅" because `RefundStatusCard` renders — but the read-path shows the lifecycle has
> **no path to `refunded`** (no `approved→refunded`, no coin/ledger post, no outbox
> event), so the refund is a permanent "pending". That is an **S** (status surface
> over a dead step), distinct from the honest **A**-absences (RT-02 return shipping,
> RT-03 photos, RT-04 history-not-surfaced). Cheapest wins: **RT-04** (surface the
> `return_status_history` rows that already exist) and closing **RT-01** (wire
> `approved→refunded` + the refund posting — *financial path, its own careful lane*).

---

## §4 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — Refund-as-coin** (`wallet_credit`) — the perpetual-cashback model; the flow
  previews `method_wallet` from `order.refund.isWallet`. (Flagged NOT-ACTIONABLE in
  the Orders audit too. NB: the return-side `buildReturnRefundView` currently
  hardcodes `original_payment` for *display* — a consistency nit, not a parity gap;
  the *model* is not flagged.)
- **D2 — Status-derived timeline** (current status → 4-state map) instead of a
  carrier-style step tracker — same intentional simplification as Orders.
- **D3 — Brand-orange tokens.**

---

## §5 — Walk slots (Salih, logged-in)

1. **Eligibility** — on a delivered order, confirm the "İade" CTA appears (and is
   absent/disabled outside the 14-day window or when fully returned).
2. **Request** — walk items → reasons → review → confirm; confirm there's **no photo
   upload** (RT-03) and **no return-cargo-code / drop-off** step (RT-02); note the
   confirm screen's "tracking_no" is just the return id.
3. **RT-05** — pick 2 items with *different* reasons; confirm only one reason
   survives (first item) + notes merged into the description.
4. **Status** — open a submitted return; confirm the timeline shows the current state
   only (no dated step history — RT-04).
5. **RT-01** — have a seller approve a return; confirm the buyer's refund card stays
   "pending"/"approved" and never reaches "refunded"/"issued" (no coin lands).
6. **History** — İadelerim list: statuses, refund amounts, empty state; confirm **no
   status filter** (RT-06).
7. **Refund method** — confirm the preview reads coin/`method_wallet` (NOT-ACTIONABLE,
   do not file).

---

## §6 — Prioritized fix list (after the walk)

> **RT-01 (the stub) ✅ DONE.** Remaining are **build-the-absent-feature** items:

1. ~~**RT-01 refund settlement**~~ ✅ RESOLVED (`feat/refund-settlement`):
   `approved → refunded` + refund-as-coin mint (D `equity:refund_distribution` ↔ C
   user wallet, migration 0082) + `ecom.return.refunded.v1` outbox → fin-svc
   `internal/refund` consumer; idempotent; card reaches "issued".
2. **RT-02 return shipping** — a return cargo code / drop-off / label so the buyer can
   actually send the item back (today there's no return-leg at all).
3. **RT-03 return photos** — damage/wrong-item evidence on the request (the upload
   pipeline exists for product photos — reuse the `POST /uploads/photos` carrier).
4. **RT-04 surface status history** — cheap: emit the `return_status_history` rows on
   `GET /returns/{id}` so the timeline is the real audit trail, not a derived state.
5. ~~**RT-06** consumer status filter on İadelerim~~ ✅ RESOLVED
   (`feat/returns-ui-polish`): client-side chip bar over the fetched list.
   **RT-05 per-item reasons** — DEFER: contract change (`reasons[] per line`)
   needs a migration + backend + codegen; out of scope for the no-codegen lane,
   re-scoped with RT-02/RT-03. See `docs/internal/returns-ui.md`.

> **Status: SEEDED — awaiting Salih's walk.** Read-path **L/S/A/U** ratings are
> CONFIRMED from source; Trendyol-side deltas firm up on the walk. **This is the last
> surface audit — with it, the parity surface map is complete** (Home, PLP, PDP,
> Search, Cart, Checkout, Orders, Returns, Account, Favorites). Remaining work is the
> cross-surface fix backlog + the deploy/cert call.
</content>
