# PD-05 — Installments (taksit) at checkout (discovery)

> Financial + PSP-gated lane (`feat/installments`). **Commit 1 = this doc only.**
> The funding model is the gate (§1.3): interest-free = surfacing + recording (no
> money-math change); vade-farkı (buyer-facing fee) = a real money change that
> STOPS for Salih's confirmation; PSP-incapable = DEFER with a plan.

## 1. What the Sipay integration supports today

- **The charge path is `POST /ccpayment/api/paySmart3D`** (`sipay/adapter.go`
  `InitiatePayment`): bearer-token auth (`/api/token`, cached 25min), body carries
  `invoice_id` (= Idempotency-Key = session_id), `total_amount` (minor-unit string),
  `currency_code`, merchant, return/cancel URLs, buyer name. **Card data never
  passes through Mopro (SAQ-A)** — the card is entered on Sipay's hosted `ccform`
  rendered in the mobile WebView / web redirect.
- **The integration already anticipates installments**: `sipay/hmac.go` defines
  `Payment3DSignFields{Total, Installment("1"|"3"|"6"|"9"|"12"), …}` +
  `SignPayment3D` per Sipay's documented paySmart3D hash algorithm — **but it is
  unused in the live path** (only tests): today's `initPayReq` sends **neither**
  `installments_number` **nor** `hash_key`. So Sipay-side capability exists and was
  designed for; the field was simply never threaded.
- **Per-BIN plan listing is architecturally unavailable**: Sipay's plan/rate query
  (`getpos`) takes the card BIN — which Mopro **never sees** (SAQ-A; the card is
  typed on Sipay's hosted form *after* we initiate). Any client-side plan list is
  therefore **generic** (1/3/6/9/12), not per-card; an unsupported card/installment
  combination is rejected by Sipay/bank inside the 3DS flow. This is a discovery
  shift: "surface the PSP-returned plans" is not possible pre-card-entry in the
  hosted-form architecture — only "offer the generic counts the merchant account
  accepts, pass the choice through".
- **No sandbox credentials available** (known constraint — the 3DS charge has
  never been live-exercised in dev). Whatever ships is verifiable to the request
  shape + hash + recording, not to an end-to-end sandbox charge.

## 2. Money-path facts (financial-core / §4)

- `total_amount` is asserted end-to-end: the webhook (`ConfirmWebhook`) verifies
  the SHA-512 hash over `total_amount` and the capture path posts the ledger entry
  from the **order's** charged total (display==charge is a guarded invariant —
  CT-09/CT-03 asymmetry tests). A buyer-facing vade-farkı would make the PSP-charged
  total ≠ order total → breaks the capture ledger symmetry, the refund math, the
  cashback base, and the coupon/discount display==charge guards — i.e. **a real
  money change** touching order pricing, orderledger, refund, and possibly new
  accounting (§12 territory).
- Interest-free (faizsiz) passes `installments_number` with an **unchanged**
  `total_amount`: the buyer pays the same total in N bank-side slices; Mopro's
  receivable is unchanged (the PSP merchant commission per installment count is a
  Mopro cost-side concern in the Sipay merchant panel, not buyer-facing). **No
  Mopro money-math change**; the work is: UI picker → thread the field through
  checkout → `paySmart3D` (`installments_number` + the already-built
  `SignPayment3D` hash) → record the chosen count on the payment/order.

## 3. Where the work lands (interest-free scope)

- **Mobile**: `checkout_payment_screen.dart` has the payment-method radio
  (`card` / `bank_transfer` / `cashback`-disabled). The installment picker renders
  under `card`. The selection threads `CheckoutController.placeOrder` →
  `checkout_repository` → `POST /checkout/initiate` body.
- **Backend**: `checkoutInitiateRequest` → `InitiateCheckoutRequest.Installments`
  → saga → `payment.InitiatePaymentRequest.Installments` → `sipay.initPayReq.
  installments_number` (+ `SignPayment3D` hash_key). Recording: additive column on
  `order_schema.payments` (and/or the checkout session); surfaced on the order
  payment view. Spec/codegen for the request field + contract test.
- **Idempotency unchanged** (session-keyed); §5 untouched (no cross-schema).

## 4. The gate — question for Salih (asked before any implementation)

1. **Interest-free v1 (likely-shippable):** generic 1/3/6/9/12 picker, unchanged
   total, choice passed to Sipay + recorded. PSP commission deltas stay a
   merchant-panel concern. Per-BIN rates/plans: DEFER (needs BIN we don't have).
2. **Vade-farkı (buyer-facing fee):** total changes → order pricing + ledger +
   refund + cashback math — §4/§12; needs a confirmed fee schedule from the Sipay
   merchant agreement → likely DEFER with an ADR plan.
3. **Full DEFER:** don't ship a picker that can't be sandbox-verified until Sipay
   credentials exist.

**Recommendation:** (1) — it matches the TR-common faizsiz pattern, changes no
money math, and the request-shape/hash/recording are all testable blind; the
3DS-time rejection path (unsupported combo) degrades exactly like any failed 3DS
today (saga compensation already handles PSP failure).
