# Quick cross-surface functional gaps — AC-02 / RT-04 / OR-04 (discovery)

Three confirmed, cheap functional gaps from the surface audits, each **read-path
verified cheap** before building (the cart-stub lesson). Local-verify; no deploy.

## AC-02 — wire the dead Help button

- **The gap (confirmed):** `mobile/lib/features/account/account_screen.dart:768` —
  the guest-menu Help row is `onTap: () {}` (dead). It is the **only** Help entry in
  the account surface (grep: one `account.menu_help`).
- **The target exists (real):** `GoRoute(path: '/help') → HelpIndexScreen`
  (`app_router.dart:608`), backed by `internal/help`/`internal/support` + the
  `mobile/lib/features/help/*` screens. Public content (guest-reachable).
- **Fix:** route the dead `onTap` → `context.push('/help')`. One line. i18n key
  `account.menu_help` already exists.
- **Cheapness: CONFIRMED** (UI-only one-liner over a real route).

## RT-04 — surface the return status history

- **The gap (confirmed):** `order_schema.return_status_history` rows ARE written
  (`InsertReturnStatusHistory`, migration 0070: `return_id, status, note, created_at`)
  but **never read** — there is no repository read method, and `handleGetReturn`'s
  `returnJSON` omits history. The mobile `return_detail_screen` renders an
  `OrderStatusTimeline` *derived from the current status* (a 4-state map), not the
  audit trail.
- **Fix (data exists; read + display):**
  1. `ReturnStatusEvent{Status, Note, CreatedAt}` + `ReturnRepository.
     ListReturnStatusHistory(returnID)` + `pgxReturnRepository` impl
     (`SELECT status, note, created_at … ORDER BY created_at`).
  2. `ReturnService.GetReturnHistory(userID, returnID)` — ownership-scoped (reuses
     `GetReturn`'s owner check), so non-owners get `ErrReturnNotFound`.
  3. `handleGetReturn` adds `history: [{status, note, created_at}]` to `returnJSON`.
  4. Mobile: `ReturnDetailDto.history` + render the real event list (fall back to the
     derived timeline when empty, e.g. pre-history returns).
- **Interface churn:** `ReturnRepository` gains a method → the `fakeReturnRepo` test
  double needs a one-line stub. `ReturnService` gains `GetReturnHistory`. No codegen
  (returns is hand-written `returnJSON`, like favorites/reviews).
- **Cheapness: CONFIRMED** (the rows exist; this is read + render, no new write/state).
- **Out of scope:** RT-01 (refund *settlement* — `approved→refunded` + coin post) is a
  financial-path lane, NOT this; RT-04 only exposes the history that's already recorded.

## OR-04 — reorder (re-add an order's items to the cart)

- **The path exists (real):** `cart.Service.AddItem(userID, variantID, qty)` →
  `POST /cart/items` (`handleCartAddItem`); mobile `cartProvider.addItem({productId,
  variantId, qty})` → `cartRepository.addItem` → `POST /cart/items`. `OrderItemDto`
  already carries `productId`, `variantId`, `qty`.
- **Fix (frontend-only, reuse the add path):** a "Tekrar sipariş ver" action on the
  order detail that loops the order's items through `cartProvider.addItem`, catching
  per-item failures (out-of-stock / `ErrVariantNotFound` → the handler returns 404/422
  and `addItem` rethrows), then navigates to `/cart` with a snackbar reporting how
  many were added vs unavailable. No backend change.
- **Cheapness: CONFIRMED** (reuses the existing add endpoint; graceful per-item
  failure handling is the only logic).

## Read-path summary

| Gap | Audited as | Read-path reality | Verdict |
|---|---|---|---|
| AC-02 Help | stub (dead button) | dead `onTap` + real `/help` route | cheap ✓ |
| RT-04 history | absent (not surfaced) | rows written, no read method | cheap ✓ (add read + render) |
| OR-04 reorder | absent | cart add path + order items both real | cheap ✓ (frontend-only) |

All three are as-cheap-as-audited — no escape-hatch deferral needed.
</content>
