# OR-02 — Order delivery-address capture (discovery)

> Orders never record a ship-to address. Checkout selects an `Address` only to derive
> the PSP buyer name; the address itself is dropped on the floor. OR-02 captures the
> selected address as an **immutable snapshot on the order** and renders it on the
> order detail. This doc is the discovery commit; implementation follows per-concern.

---

## 1. Where addresses live today

`identity_schema.addresses` (migration `0056_addresses`), owned by `internal/identity`.

| Field | Storage | PII? |
|---|---|---|
| `name_enc`, `phone_enc`, `full_address_enc`, `neighborhood_enc` | AES-GCM (`pkg/crypto.EncryptPII`) | **yes** |
| `label`, `district`, `city`, `postal_code` | plaintext (logistics routing) | no |
| `is_default`, timestamps | plaintext | no |

`identity.Service` is the public seam:
- `GetAddress(ctx, userID, addressID) (Address, error)` — returns the **decrypted**
  `Address` (service-layer `decryptAddress`; the repo stores ciphertext).
- CRUD is encrypted in the service (`encryptAddressInput`) → repo stores `AddressRow`.

The address book CRUD is **out of scope** for OR-02 (anti-goal §4.2). We only *read*
a saved address at checkout and copy it.

## 2. The checkout flow + how the PSP buyer name is derived

Live mobile path: `POST /checkout/initiate` → `order.HandleInitiateCheckout` →
`orderService.InitiateCheckout` (the v8 saga: split cart by seller → N orders + one
`checkout_session` → PSP → 3DS). The legacy `order.Checkout` / `POST /orders/checkout`
is admin/internal and is **not** the mobile path.

Today the buyer name reaches the order via the **client**, not the address:

- Mobile `CheckoutController.placeOrder` takes `state.selectedAddress` and splits
  `address.name` → `buyerName` / `buyerSurname` (`checkout_controller.dart`).
- `checkout_repository_impl.dart` POSTs `{buyer_name, buyer_surname, buyer_email,
  return_url}` — **no address**. `checkoutInitiateRequest` mirrors that.
- The saga forwards `BuyerName/BuyerSurname/BuyerEmail` to `payment.InitiatePayment`
  only (Sipay buyer block). Nothing about the address is persisted.

So the `address_id` the user picked is known **only on the client** and is discarded
after the buyer name is extracted. **The fix threads `address_id` through to the
backend and snapshots the resolved address onto each per-seller order.**

## 3. The order schema + response

- `order_schema.orders` / `order_schema.order_items` (owned by `internal/order`).
  Orders are append-mostly immutable records; only `status` / `delivered_at` mutate.
- `GET /orders/{id}` → `handleGetOrder` emits `{order, items, actions, refund}` where
  `order` is the `order.Order` struct serialized by its JSON tags, and `items` is the
  §5-safe catalog-enriched line (`enrichOrderItems`, OR-05). The mobile `OrderDto`
  (hand-written, not codegen) reads `json['order']` directly.
- `order.Order` already snapshots seller-funded discounts at sale time (CT-09/CT-03):
  the precedent is **freeze the value onto the order, don't reference it live**.

## 4. The §5 boundary — snapshot, not reference

`identity_schema` and `order_schema` are different schemas (both in `postgres-ecom`).
A cross-schema `JOIN` is **forbidden** (CLAUDE.md §5), and an FK from `orders` to
`identity_schema.addresses` would be wrong anyway: addresses are **mutable** (the user
can edit/delete a saved address), but an order's ship-to is an **as-of-purchase fact**
that must never change. Therefore:

- The order **owns** a denormalized copy in its own schema:
  `order_schema.order_addresses` (1:1, `order_id` PK).
- Capture path: order service resolves the address via `identity.Service.GetAddress`
  (in-process interface call, §3.1) **once before** the persist tx, then inserts the
  snapshot **inside** the same tx as the order rows.
- The order package stays decoupled from `identity`: it depends on a narrow
  `order.AddressResolver` interface; the composition root (`cmd/core-svc`) wires an
  adapter over `identity.Service`. No `internal/order` → `internal/identity` import.

### PII parity (§6)
The snapshot re-duplicates PII (recipient name, phone, full address, neighborhood),
so it is **AES-GCM encrypted at rest** in `order_schema` exactly as in
`identity_schema` — encrypt at repo write, decrypt at repo read (`pkg/crypto`).
`district`/`city`/`postal_code`/`label` stay plaintext, matching the source table.

## 5. Idempotency — capture is once-only with the order

`InitiateCheckout` is idempotent on `session_id` (= `Idempotency-Key`): a retry finds
the existing `checkout_session` and returns early **without** re-running the persist
tx, so the snapshot is written exactly once. Within the tx, `order_addresses` is keyed
by `order_id` (PK) and inserted `ON CONFLICT (order_id) DO NOTHING` as belt-and-braces
against any future re-entry. Legacy orders (no `address_id`) simply have no snapshot →
`delivery_address` is null/omitted and the card doesn't render.

## 6. Plan (one commit per concern)

1. **Migration `0093`** — additive `order_schema.order_addresses` (order_id PK FK →
   orders, encrypted PII cols + plaintext logistics cols). Backward-compatible: legacy
   orders have no row.
2. **Domain + repo** — `order.OrderAddress`, `Order.DeliveryAddress *OrderAddress`,
   `InsertOrderAddress` (encrypt) / `GetOrderAddress` (decrypt), attached in
   `service.GetOrder` (read path only; financial `repo.GetOrder` callers untouched).
3. **Checkout capture** — `AddressID` on `InitiateCheckoutRequest` +
   `checkoutInitiateRequest`; `order.AddressResolver` dep; snapshot in the saga tx;
   `cmd/core-svc` identity adapter wiring.
4. **Spec + codegen + contract test** — `DeliveryAddress` schema on `Order`,
   `address_id` on the checkout request; regen Go + Dart; live-handler contract test.
5. **Mobile** — send `address_id`, `OrderDto.deliveryAddress`, delivery-address card
   on the order detail, i18n keys, rebaseline goldens.
6. **Audit + ledger** — OR-02 → resolved.
