# P-034 Shipping-ETA infrastructure — design (enabler for P-007 PDP delivery-ETA)

> Filed by P-007's Outcome-C discovery (`docs/internal/p007-delivery-eta.md`): a pre-purchase PDP
> delivery line ("1-2 iş gününde kargoda") can't be computed because the two foundational inputs —
> **seller dispatch origin** and a **zone/transit-days model** — are both absent, and the only existing
> estimate (`shipping.CalculateRate.EstimatedDays`) is a live carrier call unsuitable for a PDP. This
> doc designs the missing infra: a seller-declared origin, a seeded zone/transit lookup in `ref_schema`,
> a **cheap table-driven** `shipping.EstimateETA` (no carrier call), and a PDP surface + widget. With
> this in place P-007 becomes a normal Outcome-A follow-up. **Design only — no code in this PR.**

## 0. Premise check (what discovery already established)

From `p007-delivery-eta.md`, re-verified against current code:

| Claim | Verified |
|---|---|
| Seller origin absent | ✅ `seller_schema.sellers` (0078) has no warehouse/city/zone column; `ShipmentInput.SellerAddressRef int64` (`internal/shipping/domain.go:66`) is a bare ref with **no backing origin model** — set by the checkout caller, nothing populates it from seller data |
| No zone/transit model | ✅ no zone table, no transit matrix anywhere in `migrations/` or `internal/shipping/`; `ref_schema.business_calendars` counts business days, it is **not** a transit model |
| `CalculateRate` is checkout-time | ✅ `Service.CalculateRate(ctx, carrier, ShipmentInput) → RateResult{EstimatedDays}` is a live per-call carrier hit needing a full `ShipmentInput` (origin+dest+dims) |
| User dest present, guests have none | ✅ `identity.Address` carries `District/City/PostalCode`; guests carry nothing |
| PDP resolves the seller already | ✅ `handleGetProductDetail` (`cmd/core-svc/catalog_handlers.go:185`) already calls `sellerSvc.GetByID(p.SellerID)` for seller_name/slug — the natural splice point for an ETA block |

Module homes (CLAUDE.md §2.3): origin lives in **`internal/seller`** (core-svc, owns `seller_schema`); the
zone/transit lookup lives in **`ref_schema`** (core-svc, postgres-ecom); the estimator lives in
**`internal/shipping`** (core-svc); the PDP surface is the existing catalog detail handler. **All core-svc,
all in-process Go calls — no new cross-binary path, no event, no carrier integration.**

## 1. Design shape — cheap, table-driven, honest

The PDP estimate is `transit_days(originZone, destZone)` + a handling allowance, computed from **static
reference data**, never a live carrier call. Three pieces:

1. **Seller dispatch origin** — a city the seller declares; resolved to a coarse **zone** for lookup.
2. **Zone + transit-days reference data** in `ref_schema` (readable by every module per §5) — `(city → zone)`
   and `(origin_zone × dest_zone → min/max business-days)`, seeded for TR, market-keyed for global-ready.
3. **`shipping.EstimateETA`** — a pure lookup returning a `(minDays, maxDays, confident)` range, with a
   **guest fallback** (no dest → a conservative national range, clearly labelled "tahmini").

Surfaced on the PDP detail response + a `PdpDeliveryInfo` widget. No SLA promise (§9 anti-goal): the widget
copy is an estimate ("tahmini ... iş gününde kargoda"), and a low-confidence/guest estimate is labelled as
such rather than asserting a firm number.

## 2. Seller dispatch origin (§ enabler-1)

**Migration `0084_seller_dispatch_origin`** — add to `seller_schema.sellers`:

```sql
ALTER TABLE seller_schema.sellers
    ADD COLUMN dispatch_city TEXT,           -- seller-declared dispatch city (source of truth); NULL = unknown
    ADD COLUMN dispatch_zone TEXT;           -- denormalized zone resolved from dispatch_city at write time
```

- Both **nullable**. Legacy/seed sellers (and any seller that hasn't declared an origin) carry `NULL` →
  the estimator treats them as the **conservative national fallback** (§5), never a hard failure.
- `dispatch_zone` is **denormalized** (resolved from `dispatch_city` via `ref_schema.shipping_zones` at the
  moment of write) so the PDP read is a single cheap field, not a join on every product load. This mirrors
  the established "denormalize the hot read field" pattern (e.g. `product_id` on `variant_price_history`,
  0083). Re-resolution on city change is the writer's job.
- **Onboarding capture is out of scope.** Sellers today are administrative/seeded (0078 has no onboarding
  flow). For P-034 the origin is set by **seed + an admin/CLI path**; a buyer-facing seller-onboarding form
  that *captures* dispatch city is a separate Tranche-5 surface (noted §7). The column + estimator land now
  so the data model is ready; population is incremental.
- Seed the three example sellers (0078) with TR dispatch cities (e.g. İstanbul) so fresh DBs render an ETA.

**Domain + Service:** add `DispatchCity *string` / `DispatchZone *string` to `seller.Seller`
(`internal/seller/domain.go`) and surface them through the existing `GetByID`/repo scan — no new Service
method; the PDP handler already holds the `seller.Seller`.

## 3. Zone + transit-days reference data (§ enabler-2)

Lives in **`ref_schema`** — the one schema every module may read (CLAUDE.md §5), and the correct home for
market-configurable static data (global-ready: "adding a market = config + seed + translation, zero code").

**Migration `0085_shipping_zones`** (table shapes; TR seed in the same migration / init seed):

```sql
-- city → coarse zone, per market. Zones are a small fixed set (e.g. TR: marmara,
-- ege, ic_anadolu, akdeniz, karadeniz, dogu, guneydogu) — NOT 81 provinces.
CREATE TABLE ref_schema.shipping_zones (
    market    TEXT NOT NULL,                 -- 'TR' (NOT hardcoded in code; read from config/ref)
    city      TEXT NOT NULL,                 -- normalized city key (lower, ascii-folded)
    zone      TEXT NOT NULL,
    PRIMARY KEY (market, city)
);

-- origin_zone × dest_zone → transit business-day range, per market.
CREATE TABLE ref_schema.transit_days (
    market         TEXT NOT NULL,
    origin_zone    TEXT NOT NULL,
    dest_zone      TEXT NOT NULL,
    min_days       SMALLINT NOT NULL CHECK (min_days >= 0),
    max_days       SMALLINT NOT NULL CHECK (max_days >= min_days),
    PRIMARY KEY (market, origin_zone, dest_zone)
);

-- one conservative national fallback per market, used when origin OR dest zone is unknown.
CREATE TABLE ref_schema.transit_default (
    market    TEXT PRIMARY KEY,
    min_days  SMALLINT NOT NULL,
    max_days  SMALLINT NOT NULL
);
```

- **Coarse zones, not provinces.** The matrix is `Z×Z` (≈7×7 for TR ≈ 49 rows), not 81×81 — cheap to seed,
  cheap to query, good enough for a "1-2 / 2-3 iş günü" estimate. Intra-zone is the smallest range.
- `transit_default` is the single source for the guest / unknown-origin range (e.g. TR 1–4 business days)
  so the fallback is **data**, not a hardcoded literal in Go (§ CLAUDE.md §2.2: no market constants in code).
- All static reference data → owned by `ref_schema`, seeded like `commission_rules` / `business_calendars`.

## 4. The estimator — `shipping.EstimateETA` (§ enabler-3)

New method on `shipping.Service` (`internal/shipping/api.go`), **pure DB lookup, zero carrier calls**:

```go
// EstimateETA returns a pre-purchase delivery-time estimate (business days) from a
// seller's dispatch origin to an optional destination city. It performs only static
// ref_schema lookups — NO carrier call — and is safe to call on every PDP load.
// destCity == nil (guest / no address) returns the conservative national fallback.
EstimateETA(ctx context.Context, market, originCity string, destCity *string) (ETAResult, error)

type ETAResult struct {
    MinDays   int
    MaxDays   int
    Confident bool   // false → derived from transit_default (guest/unknown origin or dest)
}
```

Resolution order (each fall-through degrades `Confident` to false, never errors):
1. `originCity` empty/unresolvable → `transit_default[market]`, `Confident=false`.
2. `destCity == nil` → `transit_default[market]` (or origin-zone worst-case row), `Confident=false`.
3. both resolve to zones → `transit_days[market, originZone, destZone]`, `Confident=true`.
4. zone pair missing a row → `transit_default[market]`, `Confident=false`.

Notes:
- **Business-days framing is consistent** with the rest of the platform (`pkg/timex.AddBusinessDays`,
  CLAUDE.md §2.2/§4.7). The widget shows the day **range** ("2-3 iş gününde kargoda"); converting to a
  calendar date via `AddBusinessDays(now, maxDays, TR-calendar)` is an optional widget nicety, not required.
- Cheap read: ≤2 indexed PK lookups per call; cacheable (the matrix is tiny + static) if PDP load ever
  warrants it, but not needed at launch volume.
- This is **separate from `CalculateRate`**: that stays the checkout-time live carrier call;
  `CalculateRate.EstimatedDays` may later back a *checkout* delivery estimate (real `ShipmentInput` exists
  there) — a different post-address surface, out of scope here.

## 5. PDP surface + widget (§ enabler-4)

**Backend** — extend the detail response in `handleGetProductDetail` (it already resolves `seller.Seller`):

```jsonc
"delivery_eta": {                  // null when no origin AND no fallback (never expected post-seed)
  "min_days": 2,
  "max_days": 3,
  "confident": true,               // false → widget shows the "tahmini" hedge prominently
  "dispatch_city": "İstanbul"      // optional, for "İstanbul'dan gönderilir" copy
}
```

- `destCity`: from the authed user's **default address city** when present (`identity` already exposes
  addresses); `nil` for guests → fallback path. The handler stays a read-only orchestrator — it calls
  `shippingSvc.EstimateETA(market, seller.DispatchZone-or-City, destCity)`; no business logic inline
  (consistent with the §3.1 read-handler exception spirit).
- Spec + regenerated clients: add `delivery_eta` to the product-detail schema; regen Go (`internal/api/gen`)
  and the Dart client (`mobile/packages/mopro_api`) — `make api-gen`, then `flutter analyze`
  (per the catalog-state memo: model field adds with defaults are Dart-fake-safe).

**Mobile** — a `PdpDeliveryInfo` widget on the PDP (the dark UI P-008b referenced in the ROADMAP):
- `confident=true`  → "**{min}-{max} iş gününde kargoda**" (+ optional "{city}'dan gönderilir").
- `confident=false` → hedged "**Tahmini {min}-{max} iş günü**" — explicitly an estimate, no firm promise.
- New i18n keys in `tr-TR.json` + `en-US.json` (+ de/ar stubs). Tests assert keyed output per the
  flutter-test-i18n memo (`.tr()` returns the key in tests).

## 6. Why not the rejected alternatives

- **Static hardcoded line** — rejected in P-007 (§9 SLA-promise + misleading); this design replaces it with
  per-origin/per-dest **data**, and labels low-confidence estimates honestly.
- **Live `CalculateRate` on PDP load** — infeasible (latency, cost, carrier rate limits) and needs a full
  `ShipmentInput` a PDP doesn't have. `EstimateETA` is a static lookup precisely to avoid this.
- **Province-level (81×81) matrix** — over-engineered for a "1-3 gün" estimate; coarse zones are cheaper to
  seed/maintain and accurate enough. Province granularity can refine later without an API change.
- **Storing origin only as `dispatch_city` and joining at read** — chose to also denormalize `dispatch_zone`
  to keep the PDP read a single field; re-resolve on write.

## 7. Out of scope (separate follow-ups)

- **Seller-onboarding capture** of dispatch city (Tranche-5 seller surface) — P-034 lands the column +
  estimator + admin/seed population; the onboarding form is a separate PR.
- Carrier API integration / real-time rates; admin zone-matrix tooling; checkout-flow delivery estimate
  (the `CalculateRate` post-address surface); province-level refinement; non-TR market seeds beyond the
  global-ready table shape; legal/CX copy review of the widget wording.
- **P-007 itself** — once this infra ships, P-007 is a normal Outcome-A follow-up (wire the widget + close
  the parity finding).

## 8. CLAUDE.md compliance check

- §2.3 paths: `internal/seller`, `ref_schema`, `internal/shipping`, catalog detail handler — all core-svc;
  no 4th binary, no new language, no new RPC. ✅
- §2.2 / §11: no `TR`/market/currency literal in business code — market read from config, all transit data
  in `ref_schema`. ✅
- §5: zone/transit data in `ref_schema` (readable by all); seller origin in `seller_schema` (owned by
  `internal/seller`), read via the seller Service — **no cross-schema JOIN**. ✅
- §3.1: PDP handler reads via Service, no new business logic inline. ✅
- §4.6: no money/float involved; days are SMALLINT. ✅
- No event/outbox/ledger path touched (this is read-only discovery infra). ✅

## 8a. As-built deviations (implemented in this PR)

Two pragmatic simplifications from §2/§5 above, decided during implementation:

- **Seller origin stores `dispatch_city` only — no denormalized `dispatch_zone`.** §2 proposed also
  caching the resolved zone on the seller. As built, `shipping.EstimateETA` resolves *both* origin and
  destination cities → zones inside one joined `ref_schema` query (`LookupTransit`), so a denormalized
  zone bought nothing at PDP volume (a 2-row PK/indexed lookup) and would add write-time coupling. Migration
  `0084` adds a single `dispatch_city TEXT` (normalized ASCII key); seeded İstanbul/İzmir/Ankara for the
  three example sellers.
- **`dest_city` is a real query param on `GET /products/{id}`** (and a generated-client param), not derived
  server-side from the authed user's address. The handler reads `?dest_city=` and passes it (or nil for a
  guest) to `EstimateETA`; the client supplies the user's selected delivery city. Auto-filling it from the
  authed default address stays a client concern (keeps the catalog handler free of identity/address
  coupling). Adding the param regenerated `CatalogApi.getProduct` with a `destCity` arg, which required
  updating the 10 `getProduct` test fakes (the documented "regen breaks Dart method-param fakes" gotcha).

Engine, schema, surface, and widget otherwise match the design. **Goldens:** the PDP gained a visible
`PdpDeliveryInfo` row, so the Linux-baselined PDP goldens are stale and must be regenerated with
`make update-goldens` on Linux/CI (the platform guard forbids re-baselining on macOS; there is no golden CI
job, so this is non-blocking).

## 9. Commit plan (for the implementing PR — not this one)

1. this doc.
2. migration `0084_seller_dispatch_origin` (columns + seed cities) + `seller.Seller` fields + repo scan.
3. migration `0085_shipping_zones` (`shipping_zones`, `transit_days`, `transit_default` + TR seed).
4. `shipping.EstimateETA` (Service + Repository + ref-lookup) + unit/integration tests (zone hit, guest
   fallback, unknown origin, missing pair, intra-zone min-range).
5. PDP `delivery_eta` in `handleGetProductDetail` + spec + regenerated Go/Dart clients.
6. `PdpDeliveryInfo` widget + i18n + flutter tests.
7. docs closure — audit (P-034 resolved → P-007 unblocked, schedule P-007 follow-up), ROADMAP, REPORT.
