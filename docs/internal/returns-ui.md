# Returns UI — read-path discovery (RT-06 / RT-05)

> Scope note: this lane is **no-codegen** to stay parallel-safe with the OR-02
> codegen lane. Discovery decides RT-05 ship-vs-defer. Read-paths confirmed
> against the live code, not assumed.

## Return-history list (RT-06)

- **Screen:** `mobile/lib/features/order/presentation/returns_list_screen.dart`
- **Provider:** `mobile/lib/features/order/application/returns_provider.dart`
  - `returnsProvider` → `AsyncValue<List<ReturnListItemDto>>`, fetched once via
    `OrderRepository.listReturns()`.
- **List item DTO:** `ReturnListItemDto` (`return_dto.dart`) carries `status`
  (one of `ReturnLifecycle.{pending,approved,rejected,refunded}`), `reason`,
  `refundAmountMinor/Currency`, `createdAt`.
- **Status chip:** `return_status_chip.dart` already maps each lifecycle to a
  colour pair, so the filter chips can reuse the same status vocabulary.

**RT-06 verdict: SHIP, pure client.** The full list is already fetched and each
item carries `status`. A client-side filter over the in-memory list needs **no
backend, no provider fetch change, no codegen** — a `StateProvider<String?>`
selected-status + a filtered view in the screen.

## Return detail (RT-05)

- **Screen:** `mobile/lib/features/order/presentation/return_detail_screen.dart`
- **Detail DTO:** `ReturnDetailDto` (`return_dto.dart`) — has a **single**
  top-level `reason` + `description`, and `items: List<ReturnItemDto>`.
- **`ReturnItemDto`** carries only `orderItemId` + `quantity`. **No per-item
  reason field.**
- **Backend confirms the single-reason contract:**
  - `internal/order/returns.go` — `ReturnItem{ID, ReturnID, OrderID,
    OrderItemID, Quantity}` (no reason); the reason lives on the `Return`
    header only (`Return.Reason ReturnReason`).
  - `migrations/ecom/0070_returns.up.sql` — `return_items(id, return_id,
    order_id, order_item_id, quantity)` has **no reason column**; `reason` is
    on the `returns` header row.
  - Audit RT-05 row already records this: the flow *collects* a per-item reason
    + note client-side but **folds it into the single-reason header contract**
    (first item's reason; notes → `description`).

**RT-05 verdict: DEFER.** The return-detail response does **not** carry per-item
reasons. Surfacing them requires:
1. a migration adding `reason` (+ note) to `order_schema.return_items`,
2. `CreateReturn` persisting per-line reasons,
3. `GetReturn` returning them,
4. an OpenAPI/spec + codegen change to add `reason` to the items array.

That is exactly the §1.3 escape-hatch case (a response/codegen change), so RT-05
is **deferred** to keep this lane no-codegen and conflict-free with OR-02. It is
re-scoped as a contract change (`reasons[] per line`) alongside the heavier
returns items (RT-02 cargo-leg, RT-03 photos).

## Shipped here

- **RT-06** — consumer status filter on return history (client-side).
- **RT-05** — DEFER (needs a per-item reason response field + codegen).
