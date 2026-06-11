# RT-01 — Refund Settlement (discovery)

> **Discovery doc — no money posted yet.** Financial-path lane. Maps the broken
> flow, the refund-as-coin ledger treatment, the outbox seam, and idempotency
> before any money code. Per the lane brief: if the ledger treatment trips
> `CLAUDE.md §12`, STOP + DEFER with an ADR plan. **Conclusion: it does NOT — this
> is IMPLEMENT** (a new equity account within §4, analogous to `cashback_distribution`).

---

## 1. The broken flow (where it stops)

`internal/order/returns.go`:
- `CreateReturn` → `pending`. **Already computes `RefundAmountMinor`** =
  Σ(`order_item.UnitPriceMinor` × qty) over the returned lines (`resolveLines`).
  That snapshot is the **charged** unit (CT-09 basket + CT-03 coupon already
  applied), so the refund matches the charge, and partial returns refund only the
  returned lines. ✅ amount source solved.
- `SellerApprove` → `transition` → `pending → approved`, writes status history.
  **STOPS HERE.**
- `ReturnRefunded` ("refunded") status **exists but nothing reaches it.** No coin
  credit, no ledger post, no outbox event.
- `cmd/core-svc/returns_handlers.go` `buildReturnRefundView` already maps
  `ReturnRefunded → "issued"` and supports `Method: "wallet_credit"` — but
  **hardcodes `original_payment`**, so even the display is wrong for the coin model.

Net: an approved return's refund card is a permanent "pending."

`ecom.payment.refunded.v1` (registry, `internal/payment/sipay`) is a **different**
flow — the PSP *fiat* refund path, `active_emitted_no_consumer`. Not refund-as-coin.

## 2. The refund-as-coin treatment (the model)

The audit fixes the model as **refund-as-coin** (`wallet_credit`) — NOT-ACTIONABLE,
not a fiat reversal of the PSP capture. So a settled refund **mints coin** to the
buyer's wallet, structurally identical to the cashback coin distribution:

**Canonical coin-mint (mirror of `internal/cashback/run_month.go`):**
```
walletPoster.PostInTx(ctx, tx, ledger.PostInput{
  Type: "refund_settlement", Currency: <COIN>, EventType: "fin.refund.coin.credited.v1",
  IdempotencyKey: "refund:<return_id>",          // UNIQUE → once-only
  Entries: [ {equity:refund_distribution:<COIN>  D amount},
             {liability:wallet:user_<id>:<COIN>  C amount} ]})
```
- `amount` = `return.RefundAmountMinor` (fiat minor, TRY) credited 1:1 as `TRY_COIN`
  (the launch peg "1 Coin ≈ 1 TL"). Coin currency from config (`DEFAULT_CASHBACK_CURRENCY`).
- Accounts resolved via `WalletPoster.FindAccount(equity:refund_distribution, COIN)` +
  `OpenOrFindUserWallet(userID, COIN)` (same interface cashback uses).
- Double-entry balanced, single-currency (§4.1/4.2), append-only (§4.3), integer
  minor (§4.6). `PostInTx` writes the fin-side outbox (`fin.refund.coin.credited.v1`).

**New ledger account:** `equity:refund_distribution` (TRY_COIN), a counter-equity
debited per refund — the exact analogue of `equity:cashback_distribution`
(`deploy/postgres-ledger/init/70-chart-of-accounts-seed.sql`). Added via a
postgres-ledger migration + the seed.

### §12 analysis — IMPLEMENT (not DEFER)
The §12 STOP list is structural: perpetual-model change, new *binary*/microservice,
bypass the multi-currency trigger, change the reference rate / 3-BD delay, hardcode
market, skip the outbox, float money, cross-module import. **None apply.** A new
equity sub-account + a new fin-svc *consumer* (same binary), following every §4
invariant and reusing the established coin-mint pattern, is normal feature work —
not "inventing financial accounting." Refund-as-coin is already the decided model
(audit), so there is no funding-model question to put to the owner (unlike the
coupon lane). Proceeding.

## 3. Trigger + transition (settle on approval)

**Decision: settle on seller approval, atomically.** No goods-receipt step exists,
and the flow is broken precisely because approval doesn't settle. `SellerApprove`
becomes: in **one core-svc tx** —
1. `UpdateReturnStatus` `→ approved` + history "seller approved",
2. `UpdateReturnStatus` `→ refunded` + history "refund issued as Mopro Coin",
3. `outbox.InsertInTx` `ecom.return.refunded.v1` (order_schema.outbox) — same tx
   (§4.5), `idempotency_key = "return:refunded:<return_id>"` (UNIQUE).

Atomic ⇒ no stuck "approved-but-not-settled" state. The coin lands when the fin-svc
consumer processes the event (eventually-consistent, like cashback); the return is
"refunded" immediately because the outbox **guarantees** delivery + the consumer is
idempotent. `returnService` gains an injected `outbox.Repository` (order_schema),
exactly as `orderService` has for `ecom.order.delivered.v1`.

Idempotency end-to-end:
- core: the `pending`-status guard makes `SellerApprove` run once (re-call →
  `ErrReturnNotPending`); the outbox UNIQUE key dedupes the event.
- fin: the consumer posts with ledger `IdempotencyKey = "refund:<return_id>"`
  (transactions UNIQUE) → coin minted once even on redelivery; + consumer-group dedupe.

## 4. Consumer home + event

New `ecom.return.refunded.v1` in `eventbus/registry.go` (producer `internal/order`,
consumer group `fin-refund-consumer`). New **`internal/refund`** module in fin-svc
(small: a consumer + a service that resolves accounts and posts the mint via
`WalletPoster`). Idempotency rides the ledger `IdempotencyKey` (no new fin table
needed — verify `PostInTx` is idempotent-on-duplicate-key during impl; if it errors
on conflict, treat conflict as already-settled). Wired as a goroutine in
`cmd/fin-svc/main.go` alongside cashback/sellerpayout/orderledger consumers.

## 5. Build order (one commit per concern)
1. migration: `equity:refund_distribution` (TRY_COIN) + chart seed (+ any hand-rolled
   e2e/integration ledger DDL — the #185 lesson).
2. core-svc: registry entry + `returnService` outbox + `SellerApprove` settlement.
3. fin-svc: `internal/refund` consumer (coin mint, idempotent) + main wiring.
4. mobile: refund card `Method: wallet_credit`.
5. tests (core settlement + idempotency; fin consumer ledger-balance + idempotency;
   e2e return→refund→coin) + goldens rebaseline + `TRENDYOL_PARITY_RETURNS_AUDIT.md`
   (RT-01 → resolved) + `CUTOVER_LEDGER.md`.

## 6. References
- `internal/order/returns.go` (lifecycle), `cmd/core-svc/returns_handlers.go` (refund view).
- `internal/cashback/run_month.go` (the coin-mint pattern to mirror), `WalletPoster` (`internal/cashback/api.go`).
- `internal/eventbus/registry.go`, `internal/order/service.go` (outbox event build).
- `deploy/postgres-ledger/init/70-chart-of-accounts-seed.sql` (chart).
- `docs/internal/financial-core.md`, `CLAUDE.md §4`/§5/§12.
