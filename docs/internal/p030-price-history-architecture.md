# P-030 Price-History (TR/EU lowest-30-day) — discovery + architecture

> Closes the **backend foundation** for PARITY_AUDIT **P-030 (HIGH, compliance)**: TR 6502 +
> EU Omnibus (2019/2161) require that an announced price reduction show the *lowest price applied
> in the 30 days before the reduction*. This doc records what discovery actually found (which
> differs materially from the PR prompt's premise), the mechanism decision, and the honest limits
> of what this PR achieves. **Frontend display is a follow-up; legal sign-off is out of scope.**

## 0. The prompt's premise vs. the codebase

The prompt assumed: paths under `services/core-svc/internal/...`, a `products.price_minor` column,
and "every code path that updates a product's price." **All three are false here.** Discovery:

| Prompt assumed | Actual |
|---|---|
| `services/core-svc/internal/storage/catalog/**` | `internal/catalog/` (3-binary monolith; CLAUDE.md §2.3) |
| price on `products` | **price is on `catalog_schema.variants`** (`price_minor`, `original_price_minor`); `products` has no price column |
| multiple price-**update** paths | **zero update paths.** Only `InsertVariant` (create). Variant prices are immutable post-creation |
| price changes over time | **prices never change.** "Discount" = a *static* `variants.original_price_minor` MSRP (0065: "strikethrough when > current price"), set at seed/creation |

## 1. Pricing inventory (§2.1)

- **Schema:** `catalog_schema.variants.price_minor BIGINT NOT NULL` (0010); `.original_price_minor BIGINT`
  nullable (0065, "null = no discount"); `.price_currency` (default TRY). `discount_price_minor` (0061)
  exists but is **unused in code** (0 references) — not tracked.
- **Representative product price:** `productSummarySelect` (repository.go:314) picks the **cheapest variant**
  via `JOIN LATERAL (… ORDER BY price_minor ASC LIMIT 1)`. So `ProductSummary.priceMinor` = min-variant price.
- **Write paths:** Go has exactly one — `repository.go:59 InsertVariant` — and it inserts only
  `(product_id, sku, color, size, price_minor, price_currency, stock, image_keys)`: it does **not** write
  `original_price_minor`. The rich pricing data (`original_price_minor`) is therefore set by **SQL seeds**,
  not the Go path. There is **no** `UpdateVariant`/`UpdatePrice` anywhere.
- **Money discipline:** BIGINT minor units throughout (CLAUDE.md §4.6). History stays minor-units.

## 2. Mechanism decision (§2.6) — **Mechanism B (DB trigger)**

The prompt defaults to Mechanism A (application-level: instrument every Go price-write). **Rejected here**
because the dominant variant-creation path is **SQL seeds**, and the one Go path (`InsertVariant`) doesn't
even set `original_price_minor`. Mechanism A would miss most price-sets and all original-price data.

**Chosen: Mechanism B — an `AFTER INSERT OR UPDATE` trigger on `catalog_schema.variants`** that records a
row in `variant_price_history` whenever a variant's `price_minor`/`original_price_minor` is set or changes.

Why B is right for *this* codebase:
- Captures **every** write path uniformly — seeds, Go `InsertVariant`, any future bulk import, and any
  future update lifecycle — so the history table is authoritative for compliance.
- Triggers are an established pattern here (ledger DEFERRABLE constraint triggers; `0057` tsvector;
  `no_update_ledger` rules). Not novel risk.
- Less code than A (no `InsertVariant` tx refactor, no per-path discipline), and idempotent: the trigger
  inserts only on INSERT or a real change (`IS DISTINCT FROM`), so a no-op update never duplicates.

Trade-off acknowledged (prompt §1.3): a trigger is a "hidden" side effect and PR #71's lint-discipline
analyzer does not observe triggers. Mitigated by documenting it here + in `docs/internal/financial-core.md`
and exercising it in integration tests (the trigger is added to the test `setupSchema` too).

## 3. Schema (§2.2) — migration `0083_variant_price_history`

```sql
CREATE TABLE catalog_schema.variant_price_history (
    id                   BIGSERIAL   PRIMARY KEY,
    variant_id           BIGINT      NOT NULL,            -- soft ref (CLAUDE.md §5 discipline)
    product_id           BIGINT      NOT NULL,            -- denormalized for the per-product MIN
    price_minor          BIGINT      NOT NULL CHECK (price_minor >= 0),
    original_price_minor BIGINT,                          -- strikethrough "was" price at this point (nullable)
    currency             TEXT        NOT NULL DEFAULT 'TRY',
    source               TEXT        NOT NULL DEFAULT 'trigger',  -- 'create' | 'update' | 'backfill'
    effective_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX vph_product_effective_idx
    ON catalog_schema.variant_price_history(product_id, effective_at DESC);
```
- No FK (soft ref per §5 discipline, even same-schema). Same-schema so no cross-schema violation.
- Per-variant grain (price is per-variant); the read aggregates to product via `MIN`.
- Reversible: down drops trigger → function → index → table.

## 4. Query (§2.3) — inline, mirrors `favorites_count`

The 30-day lowest is a correlated subquery added to `productSummarySelect` (and the `ListProductsByIDs`
select), exactly like `favorites_count` — single query, N+1-safe:
```sql
(SELECT MIN(vph.price_minor) FROM catalog_schema.variant_price_history vph
  WHERE vph.product_id = p.id
    AND vph.effective_at >= now() - INTERVAL '30 days') AS lowest_30d_price_minor
```
`vph_product_effective_idx` serves the `(product_id, effective_at)` predicate. No separate batch method.

## 5. Backfill (§2.4)

One `variant_price_history` row per existing variant, `source='backfill'`, `effective_at = now()`:
```sql
INSERT INTO catalog_schema.variant_price_history
    (variant_id, product_id, price_minor, original_price_minor, currency, source, effective_at)
SELECT id, product_id, price_minor, original_price_minor, price_currency, 'backfill', now()
FROM catalog_schema.variants;
```
From migration day every product with a variant has ≥1 history row, so `lowest_30d` is always computable.

## 6. Compliance interpretation (§2.5) — **what this PR does and does NOT achieve**

- **Does:** records every variant price-set going forward (trigger) + a backfill baseline, and exposes a
  correct `lowest_30d_price_minor` per product. This is the *technical foundation* for compliant display.
- **Does NOT make the platform compliant.** Two honest gaps remain:
  1. **No price-update lifecycle.** Variant prices are immutable post-creation, so for every product today
     `lowest_30d_price_minor == current displayed price`. History will only diverge once prices actually
     change over time. → filed as **P-032**.
  2. **The existing `original_price_minor` strikethrough is a static MSRP, not a tracked reduction.** A card
     showing "was ₺X, now ₺Y" (from `original_price_minor`) is exactly what the Omnibus regulates, yet ₺X has
     no 30-day basis. This PR makes the gap **measurable** (lowest_30d == Y ≠ the claimed ₺X) but does not
     resolve it — the fix is a policy + frontend-display decision (show "30 günün en düşük fiyatı" from
     `lowest_30d_price`, and only assert a reduction when `lowest_30d < current`). → frontend follow-up.
- **No compliance claim without legal sign-off** (prompt §4/§9). This doc + the PR provide the foundation
  and flag the interpretation for legal review.

## 7. Out of scope

Frontend display; admin price-history UI; compliance-violation alerts; the price-update lifecycle itself
(P-032); non-TR/EU jurisdictions. Tracked separately.

## 8. Commit plan

1. this doc.
2. migration `0083` (table + index + trigger function + trigger + backfill).
3. query + `ProductSummary.lowest_30d_price_minor` (repository + domain + handler mapping) + `setupSchema`.
4. spec + regenerated clients.
5. integration tests (trigger fires on insert/update; no-op no-dup; 30-day window; MIN aggregation; summary serialization).
6. docs closure — audit (P-030 backend-resolved, Mechanism B; file P-032), `financial-core.md` convention, ROADMAP, REPORT.
