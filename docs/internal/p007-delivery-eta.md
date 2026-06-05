# P-007 PDP delivery-ETA — discovery (Outcome C: blocked by shipping-ETA infra)

> The PDP should show an estimated delivery line (Trendyol parity: "Yarın kargoda" /
> "1-2 iş gününde kargoda"). **Discovery → Outcome C (blocked):** no pre-purchase ETA
> infrastructure exists — the foundational inputs (seller dispatch origin + a zone/transit-days
> model) are both absent, and the one estimate that exists is a live carrier call unsuitable for
> a PDP. Paths are `internal/shipping/` + `internal/catalog/` (the prompt's `services/core-svc/...`
> is wrong). **PDP unchanged; filed P-034.**

## 1. What shipping infrastructure exists

`internal/shipping/` is a mature **carrier-adapter** layer (aras, yurtici, surat, mng, hepsijet, ptt)
for *real outbound shipments*: `CreateLabel`, `TrackShipment`, webhooks/polling, `MarkDelivered`. Its
`Service.CalculateRate(ctx, carrier, ShipmentInput) → RateResult{CostMinor, …, EstimatedDays}` does carry
an `EstimatedDays`, parsed from the carrier's rate API.

**But `CalculateRate` is a checkout-time operation, not a PDP estimate:**
- It makes a **live external call** to the carrier per invocation — calling it on every PDP load is
  infeasible (latency, cost, rate limits).
- It requires a full `ShipmentInput` — **origin** + **destination** + package dims — none of which a PDP
  has for a guest, and whose **origin doesn't exist** in the data model at all (see §2).

`Shipment.EstimatedDeliveryAt` exists too, but it's per-shipment (post-order, after a label is created) —
also not a pre-purchase signal.

## 2. The two foundational gaps (why a cheap PDP ETA can't be computed)

A cheap, data-driven PDP ETA is `transit_days(originZone, destZone)` + handling — needing three inputs:

| Input | Present? | Notes |
|---|---|---|
| **Seller dispatch origin** (warehouse/city/zone) | ❌ **absent** | No `warehouse`/`origin`/`city` on the seller model or `0078_sellers`. Adding it is **seller-onboarding** territory (where/how a seller declares dispatch location). |
| **Zone / transit-days model** (origin×dest → days) | ❌ **absent** | No zone table, no transit-days matrix, no per-city/per-carrier static days anywhere in `migrations/` or `internal/shipping/`. (`ref_schema.business_calendars` counts business days — it is **not** a transit model.) |
| **User destination** (city/district) | ✅ present | `identity.Address` carries `District`/`City`/`PostalCode` ("stored plaintext for logistics routing") — but **guests have none**. |

With **no origin** and **no transit model**, there is nothing to compute from. There is also **no PDP
delivery slot** in the mobile code to wire (unlike P-030's pre-built `PdpPriceBlock.lowestIn30DaysMinor`).

## 3. Why not ship a static estimate

A hardcoded "Tahmini 1-3 iş günü içinde kargoda" needs no data — but it is **rejected**:
- It is a **delivery promise with no backing** — directly the §9 anti-goal ("Do not promise SLAs; this is
  an estimate, not a commitment") and a real CX/legal risk (a buyer relies on it; the platform can't honor
  a number it doesn't compute).
- No per-product / per-seller / per-destination variation → cosmetic and potentially **misleading**.
- **Worse than showing nothing** (the current honest state).

## 4. Decision — Outcome C (discovery-only); file P-034

No code change. The PDP continues to show no delivery ETA (current state). Building a real one is
architectural and out of this PR's scope (§1.2/§9): it requires seller-origin (onboarding), a
zone/transit-days model + seed, a **cheap** `ComputeETA` (table-driven, *not* a live carrier call), a PDP
widget, and a guest-fallback policy. Filed as **P-034**.

`CalculateRate.EstimatedDays` can feed a **checkout** delivery estimate later (where a real
`ShipmentInput` exists), but that is a separate, post-address surface — not the PDP.

## 5. Path forward (P-034)

1. Seller dispatch origin (city/zone) on the seller model + onboarding capture.
2. A `shipping_zones` / transit-days lookup (origin-zone × dest-zone → business-days), seeded for TR.
3. A cheap `shipping.EstimateETA(originZone, destZone|nil) → (minDays, maxDays)` (no carrier call; guest →
   a conservative range, clearly labelled "tahmini").
4. Surface on `Product`/`Variant` (or a dedicated endpoint) + a `PdpDeliveryInfo` widget + i18n.

Then P-007 is a normal Outcome-A/B follow-up with the infra in place.

## 6. Out of scope

Carrier API integration; admin shipping-zone tooling; checkout-flow changes; the P-034 infra itself;
P-033; chi-square flake; PDP-strikethrough. No migration/schema/code/tests here.

## 7. Commit plan

1. this doc.
2. docs closure — audit (P-007 → BLOCKED-BY-SHIPPING-INFRA; file **P-034**), ROADMAP, REPORT.
