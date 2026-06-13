# Seller-Entered Size Charts — design (Phase C, design-first)

Sellers enter their own size chart for their products; the match service prefers
the **seller chart** over the EN 13402-3 **standard** baseline when one exists.
This closes the accuracy gap the curation item (`chore/size-chart-curation`,
#216) deliberately left a `source` seam for — a per-garment truth beats any
standard. Completes the size-fit arc: standard baseline for everyone,
seller-precise charts where sellers invest, basic mode (warned) for the
unmeasured.

## Resolution (the whole feature in one line)

```
match precedence:  seller chart  →  EN standard baseline  →  none
                   (source=seller)   (source=standard)       (status=no_chart)
                   chart_approximate  chart_approximate        —
                   = false            = true
```

Confidence (`detailed`/`basic`) is **orthogonal** to source: it tracks whether
the *measurements* were real or estimated. A BASIC (estimated) profile stays
warned **regardless** of which chart backed it. `source` conveys chart
provenance (per-brand truth vs standard estimate); `chart_approximate` is the
honest "this isn't the real garment's chart" flag → **false only for a seller
chart**. So the four states a shopper can see:

| source | confidence | chart_approximate | meaning |
|---|---|---|---|
| seller | detailed | false | real measurements vs the actual garment's chart — highest |
| seller | basic | false | seller chart, but a measurement was estimated → warned |
| standard | detailed | true | real measurements vs EN baseline — high |
| standard | basic | true | EN baseline + estimated measurement → warned |

## Discovery shifts (vs the prompt's assumptions)

1. **The match lives in jobs-svc, but seller charts are core-svc data → core
   resolves + passes; jobs-svc never reads `seller_schema`.** This is the §5-safe
   carrier/snapshot pattern (PLP-17 official-seller merge, cart enrichment): the
   existing `GET /products/{id}/size-recommendation` handler already resolves the
   product title in-process and POSTs to jobs-svc `/internal/sizefit/recommend`.
   We extend that POST with an optional resolved seller chart. `sizefinder`
   stays storage-agnostic for seller data — it matches against whatever chart it
   is handed.
2. **`source` must become a response field.** The curation item added a `source`
   *column* but kept the `Recommendation` API shape. This feature surfaces it:
   `source: seller | standard` (empty for no_chart), plus `chart_approximate`
   flips to **false** for seller charts (the accuracy gain is the point).
3. **Confidence is NOT a third tier.** The enum stays `detailed|basic`
   (measurement realness). "Seller DETAILED = highest, standard DETAILED = high"
   is carried by `source` + `chart_approximate`, not by a new confidence value.
4. **Granularity = reusable seller *template* + per-product attach** (v1: one
   chart per product). A seller authors a chart once and attaches it to many
   SKUs instead of re-entering per product. Per-product-only would have embedded
   `product_id` on the chart; the template+attach split is barely more code and
   is the right long-term model.

## Data model (migration 0099 — additive, `seller_schema`, owned by `internal/seller`)

Seller charts are **product data, not PII** → plaintext integer millimetres (the
money-type discipline applied to lengths; *not* the §6 EncryptPII path that fit
*profiles* use). `seller_schema` is owned by `internal/seller`; all three tables
live there so resolution is a single-schema query (no §5 JOIN across schemas).

- **`seller_schema.seller_size_charts`** (header):
  `id BIGSERIAL PK · seller_id BIGINT (soft ref) · name TEXT · garment_type TEXT
   (top|bottom|dress|skirt|outerwear) · gender TEXT (female|male) · size_system
   TEXT (alpha|eu) · source TEXT DEFAULT 'seller' · created_at · updated_at`.
- **`seller_schema.seller_size_chart_rows`**:
  `chart_id BIGINT (FK → seller_size_charts, ON DELETE CASCADE) · size_label TEXT
   · sort_rank INT · measurement TEXT (chest|waist|hip) · min_mm INT · max_mm INT`
  PK (chart_id, size_label, measurement). Same `(size_label, measurement,
  min_mm, max_mm)` shape as `ref_schema.size_charts` so the match treats rows
  identically.
- **`seller_schema.product_size_charts`** (attachment, one chart per product v1):
  `product_id BIGINT PK (soft ref → catalog product) · chart_id BIGINT
   (FK → seller_size_charts ON DELETE CASCADE) · seller_id BIGINT · created_at`.

Fresh-DB init lockstep: the `seller_schema` init file (mirror the migration DDL).

## Match precedence (the resolution path)

1. **Core** (`GET /products/{id}/size-recommendation`): after resolving the
   product, core calls `seller.Service.SizeChartForProduct(ctx, productID)` →
   `(SellerChart, bool)`. One `seller_schema` query joining header+rows (same
   schema, allowed). If found, core adds it to the recommend POST body:
   `{user_id, title, seller_chart?: {garment_type, gender, rows:[...], source}}`.
2. **jobs-svc** `/internal/sizefit/recommend`: decodes the optional `seller_chart`
   and calls `svc.Recommend(ctx, userID, title, sellerChart)`.
3. **sizefinder.Recommend** gains a trailing `*SellerChart` arg:
   - `sellerChart != nil` → `garment = sellerChart.GarmentType`; `chart =
     sellerChart.Rows`; `source = "seller"`; `chart_approximate = false`. (Title
     classification is bypassed — the seller declared the garment.)
   - else → classify title → `garment`; `chart = ref_schema` gender-resolved;
     `source = "standard"`; `chart_approximate = true` (today's behaviour).
   - The rest (estimate-then-match, confidence, signal, between/edge) is
     **unchanged** — the seller chart flows through the identical machinery.

`sizefinder` never imports seller/catalog; it receives a value object. Boundary
integrity preserved.

## Write API (core-svc, role-gated `requireAuth + requireSellerRole`)

> **Discovery:** the seller console endpoints are **hand-written raw-Dio, NOT in
> the OpenAPI spec** (only `/seller/orders/{id}/breakdown` is specced; returns,
> Q&A, variant-price are all hand-written — the favorites/reviews pattern). The
> seller chart writes follow that convention → no codegen for them. The **only**
> spec/codegen change is `source` on `SizeRecommendation` (a specced consumer
> endpoint). The mobile seller console (PR #2) consumes these via raw Dio.

All writes require an `Idempotency-Key` (the existing `requireIdempotencyKey`).
Ownership is enforced in the seller repository (not-found, never an existence
leak — the `handleUpdateVariantPrice` pattern).

- `POST /seller/size-charts` — create a validated chart (body: name, garment_type,
  gender, size_system, rows[]). 201 + chart id; 422 on validation failure.
- `PUT  /seller/size-charts/{id}` — replace a chart the seller owns (rows live →
  re-rates existing recommendations). 404 if not owned.
- `GET  /seller/size-charts` — list the seller's charts.
- `POST /seller/products/{id}/size-chart` — attach `{chart_id}` to a product the
  seller owns (validated against `catalog.Product.SellerID` / `ProductIDsBySeller`
  AND chart ownership). `DELETE` to detach → falls back to the standard baseline.
- `GET  /seller/size-charts/standard?garment_type=&gender=` — the EN baseline rows
  as a **copy-from-standard** starting point (read-through to `ref_schema`).
  **Deferred to PR #2** (a UI-prefill affordance; not needed for the match path).

## Validation (hard-reject → 422; `internal/seller`)

A seller chart that fails any rule is rejected (a non-monotonic chart is a data
error, not a warning):
- garment_type / gender / size_system / measurement are valid enums.
- Each row: `300 ≤ min_mm < max_mm ≤ 2500` (reuse sizefinder's sane-bound mm
  constants — reject cm/mm slips).
- **Required measurements present** for the garment type (the EN 13402-2
  `relevantMeasurements` map: top/outerwear→chest; bottom/skirt→waist+hip;
  dress→chest+waist+hip).
- **≥ 2 sizes**, unique `size_label` per measurement, contiguous `sort_rank`.
- **Monotonic non-decreasing** across `sort_rank` per measurement: a larger
  size's min_mm/max_mm ≥ the previous size's (M ≥ S on every dimension).

## Seller UX (PR #2 — split per §4)

Seller console → "Beden tablosu": create chart (name + garment/gender/system),
enter rows by alpha and/or EU; **copy-from-standard** prefill (the
`/standard` endpoint) so sellers start from the EN baseline; attach to product(s);
edit is live. PDP optionally shows a "satıcı beden tablosu" (sized by seller) chip
when `source == seller`. i18n TR+EN; goldens on-branch.

## §5 / §6 / boundaries

- **§5:** seller chart resolution is one `seller_schema` query; the product→chart
  hop is a soft `product_id` ref (no cross-schema JOIN). jobs-svc receives a value
  object, never touches `seller_schema`.
- **§6:** unchanged — fit *profiles* stay AES-GCM encrypted; seller charts are
  product data (plaintext mm). No new PII.
- **Module map:** `seller_size_charts` is `internal/seller`-owned. `sizefinder`
  gains a value type only.

## Build plan (commit per concern)

1. Design doc (this).
2. Migration 0099 (`seller_size_charts` + rows + `product_size_charts`) + init lockstep.
3. `internal/seller`: domain types + repo (CRUD + `SizeChartForProduct`) + service validation + unit tests.
4. `internal/sizefinder`: `SellerChart` value type + precedence + `source`/`chart_approximate` on `Recommendation` + unit tests.
5. core write handlers + routes (ownership) + the recommend resolver (core → jobs payload) + jobs-svc decode.
6. Spec + codegen (new seller endpoints; `source` on SizeRecommendation) + contract tests.
7. **PR #2:** seller console UI (copy-from-standard) + PDP provenance chip + i18n + goldens.

## Split-bailout (§4)
Backend (steps 2–6) = one mergeable PR. Seller UI + PDP provenance = PR #2. If
granularity balloons, ship per-product attach first and flag reusable templates
as a follow-up (already minimal here). Never bypass validation; never JOIN across
schemas.

## Shipped — backend (PR #1)
Steps 2–6 of the build plan: migration 0099 (+init lockstep), `internal/seller`
domain/validation/repo (CRUD + attach + `SizeChartForProduct`), `sizefinder`
`SellerChart` precedence + `source` on `Recommendation`, core write endpoints +
the recommend resolver (core → jobs value object), `source` on the specced
`SizeRecommendation` + Go/Dart regen. Tests: validation table, sizefinder
precedence (seller→standard→none, BASIC-still-warned), handler status/ownership.
Migration round-trip + ON DELETE CASCADE verified on PG16. **PR #2 = seller
console UI (copy-from-standard) + PDP "sized by seller" chip + i18n + goldens.**

## Out of scope / follow-ups
- Multiple charts per product / variant-level charts (v1 is one chart per product).
- Chart versioning/history (edits are live; no audit trail yet).
- Per-brand EU/alpha auto-derivation (seller enters the system they use).
