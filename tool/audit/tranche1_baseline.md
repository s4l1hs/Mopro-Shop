# Tranche 1 baseline — orders/cancel/return/refund surface (pre-PR)

Read-only confirmation of what exists today, per §2 of the Tranche 1 prompt.
This is the input to §3: only the `Missing` rows below get implemented.

## Cancel

| Item | Finding |
|---|---|
| Endpoint | **Exists** — `POST /orders/{id}/cancel` → `handleCancelOrder` (`cmd/core-svc/main.go:1104`) |
| Service method | **Exists** — `order.Service.CancelOrder(ctx, orderID, reason)` (`internal/order/api.go:31`, impl `internal/order/service.go`) |
| Eligibility rule | **Exists** — only `pending_payment` or `paid` (`service.go` CancelOrder); else `ErrInvalidTransition` → HTTP 409 |
| Return DTO after cancel | **Gap** — handler returns `204 No Content`, not the updated order/state |
| Idempotency | **Gap** — re-cancelling a `cancelled` order returns 409, not the existing state (prompt §3.2 wants idempotent) |
| Refund in same tx | **Gap** — cancel does **not** issue a refund; refund is a separate endpoint (§3.2 wants server-driven refund on cancel) |
| Reason enum / note | **Gap** — body is free-text `{reason}` only; no enum, no `note` |

## Return

| Item | Finding |
|---|---|
| Endpoint | **Spec-only** — `POST /orders/{id}/returns` (`CreateReturn`) + `GET /orders/{id}/returns` (`ListReturns`) declared in `api/openapi.yaml:1414`, **no handler wired** in core-svc |
| `CreateReturn` signature | **Spec-only** — request `ReturnRequest` (`openapi.yaml:2533`): `reason` (enum `wrong_product,not_as_described,damaged,size_issue,changed_mind,other`), optional `description`, optional `items[]{order_item_id,quantity}`; response `Return` (`openapi.yaml:2556`): `id,order_id,status(pending/approved/rejected/refunded),reason,description,created_at` |
| Eligibility rule | **Missing** — no returnable-item / window computation anywhere |
| Reason code enum | **Spec-only** — see above (single reason per return, not per-item) |
| Returns table | **Missing** — no `returns` table; `dump_schema.sh` shows none |
| Service | **Missing** — no return service/repo |

## Refund

| Item | Finding |
|---|---|
| Endpoint | **Exists** — `POST /orders/{id}/refund` → `handleRefundOrder` (`cmd/core-svc/main.go:1133`); full refund via PSP `payment.Service.Refund`, updates payment status + order→`refunded` in one tx; requires `Idempotency-Key` |
| Eligibility | **Exists** — `paid`/`shipped`/`delivered` only |
| Refund status enum | **Partial** — `payment.PaymentStatusRefunded` on the payment row; no buyer-facing `pending/processing/issued/failed` enum |
| Refund DTO | **Gap** — handler returns `{refund_ref, refunded_at, amount_minor}`; no structured `refund{}` block on the order/return DTO (§3.4) |

## Orders DTO

| Item | Finding |
|---|---|
| `actions` / eligibility field | **Missing** — `handleGetOrder` returns `{order, items}` raw (`main.go:1010`); `order.Order` struct (`internal/order/domain.go`) has no `actions`. Frontend currently computes `OrderStatus.canCancel` client-side (`order_detail_screen.dart:151`) — exactly the client/server split §3.1 wants to remove |
| `OrderItem` shape | **Exists** — `id, order_id, variant_id, qty, unit_price_minor, …` (`domain.go`); enough to drive returnable-item math |
| `delivered_at` | **Exists** — `Order.DeliveredAt *time.Time`; basis for the 14-day return window |

## Returns list / detail endpoints

| Item | Finding |
|---|---|
| `GET /returns` (global) | **Missing** — spec only has per-order `GET /orders/{id}/returns` (`ListReturns`) |
| `GET /returns/{id}` (detail) | **Missing** |

## Order status enum

`internal/order/domain.go`: `pending_payment, paid, shipped, delivered,
cancelled, refunded, partially_refunded`. **No** `return_requested` /
`return_approved` / `return_rejected` / `refund_issued` order statuses. The
`Return.status` enum (`pending/approved/rejected/refunded`) is a separate
per-return lifecycle, not an order status.

## Frontend

| Item | Finding |
|---|---|
| `OrderStatusTimeline` widget | **Missing** — the prompt §8 assumes one exists; only `order_status_chip.dart` (a single status chip) exists. §8 must build a timeline fresh (documented adaptation), not "enhance" a non-existent widget |
| Cancel UI | **Exists** — `order_detail_screen.dart:151` already renders a cancel button + `_confirmCancel` AlertDialog using client-side `OrderStatus.canCancel`; §4/§5 replace this with server-driven `actions` + adaptive `CancelOrderDialog` |
| Returns route | **Missing** — no `/returns` or `/orders/:id/return` in `app_router.dart` |
| Account rail | `account_left_rail.dart:53` has Orders + Wallet rows; §9.3 inserts "İadelerim" between them |

## Net scope decisions (adaptations, per §16)

1. **Return model follows the OpenAPI contract, not the richer prompt model.**
   The spec already defines `ReturnRequest`/`Return` with a *single* `reason`
   per return (+ optional per-item quantities) and statuses
   `pending/approved/rejected/refunded`. Implementing against the spec avoids
   inventing a parallel per-item-reason surface. Per-item reason codes,
   `return_status_history`, and `returnableUntil` on each item are folded in as
   **extensions** where cheap (status history table, window computation) and
   noted as Backlog where they would fork the contract.
2. **Returns list is per-order in the spec; the buyer-facing global "İadelerim"
   list (`/returns`) is an added read endpoint** backed by the same table.
3. **`OrderStatusTimeline` is new, not an enhancement** (no prior widget).
4. **Refund visibility is read-only** — surfaced from the existing payment/refund
   record; no new ledger writes (CLAUDE.md §4/§9 keep refund issuance in the
   existing PSP path).
