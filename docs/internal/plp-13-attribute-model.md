# PLP-13 — product attribute model + faceting — design (build DEFER'd)

> Track D of the PLP-completion work order. PLP-13 = Trendyol's deep,
> **category-aware** attribute facet stack (storage / RAM / screen / colour /
> condition / camera …). Mopro has no normalized attribute model. **The design
> is the deliverable**; the build is genuine multi-phase schema work → DEFER'd
> with the phased plan below (per Track D's own framing).

## 1. Current state

- **`catalog_schema.variants.color` + `.size`** — structured TEXT columns, but
  **not** filter params and **sparse** (`''` default for most SKUs).
- **`catalog_schema.products.specs`** — **opaque JSONB** (migration 0061), with
  **arbitrary per-category keys** (`{pages, isbn}` for books, none for clothing).
  No schema declares which keys are facetable per category; no GIN/path index; no
  value normalization (units, casing).
- **No** `product_attributes` / `attribute_keys` / `category_facets` table; **no**
  facet-aggregation (values + counts) surface. Brand/rating faceting works because
  those are first-class columns — attributes are not.

→ Faceting on opaque `specs` keys would be a fragile, category-coupled hack
(anti-goal). The real fix is a **normalized attribute model**.

## 2. Proposed normalized model (catalog_schema only — §5-safe)

```
attribute_keys      (id, slug, name_tr, name_en, data_type)        -- 'depolama','renk','ekran_boyutu'…
                    -- data_type ∈ text | number | bool; number carries an optional unit slug

category_facets     (category_id FK ref_schema.categories,          -- which attributes are facetable
                     attribute_key_id FK, display_order, searchable) --   per category (Trendyol's
                    PRIMARY KEY (category_id, attribute_key_id)       --   category-aware stack)

product_attributes  (product_id FK, attribute_key_id FK,            -- normalized per-product values
                     value_text, value_num)                          --   (one row per (product, key, value))
                    INDEX (attribute_key_id, value_text)             -- facet aggregation
                    INDEX (product_id)                               -- per-product lookup
```

- `category_facets` makes facets **inherit down the subtree** (pair with PLP-12:
  a parent category's facets = the union over its descendants, or an explicit
  rollup config).
- Values are **normalized** at write time (canonical casing/units) so aggregation
  buckets are clean.

## 3. Faceted aggregation (mirror brand/rating)

Given a category (+ its PLP-12 subtree) and the active filters, for each
`category_facets` attribute return `(value, count)` buckets:

```sql
SELECT ak.slug, pa.value_text, count(DISTINCT pa.product_id)
FROM catalog_schema.product_attributes pa
JOIN catalog_schema.attribute_keys ak ON ak.id = pa.attribute_key_id
WHERE pa.product_id IN (<the filtered product set for this category subtree>)
  AND pa.attribute_key_id IN (SELECT attribute_key_id FROM catalog_schema.category_facets WHERE category_id = ANY($subtree))
GROUP BY ak.slug, pa.value_text;
```
Surfaced either as a new `GET /categories/{id}/facets` endpoint or a `facets`
block on the `listProducts` response. **Filter:** `attr[<slug>]=v1,v2` params →
`product_attributes` `EXISTS`/`IN` predicates in `appendProductFilters`.

## 4. UI

Attribute accordions in the desktop `FilterPanel` + mobile `PlpFilterSheet`,
reusing the **`PlpBrandFacet`** pattern (searchable when long, value+count rows,
live-applied, removable chips). Driven by the server facet buckets.

## 5. Phased plan

- **Phase 0 — this design.** ✅
- **Phase 1 — schema + 1–2 high-value attributes.** Migrations for the 3 tables;
  backfill `renk` from `variants.color` and one `specs` key (e.g. `depolama` for
  phones) into `product_attributes`; seed `category_facets` for those; **one**
  facet-aggregation surface + filter param + the accordion UI for those attrs.
  *Still a full schema+codegen+UI vertical — not "contained" enough for the batch.*
- **Phase 2 — coverage.** Backfill remaining `specs` keys per category with value
  normalization; populate `category_facets` for the launch categories; the
  attribute-write path (seller PUT / ingest) populates `product_attributes`.
- **Phase 3 — polish.** Searchable long facets, counts, range facets (numeric),
  unit display; facet caching.

## 6. Verdict

**DEFER the build** (multi-phase schema + backfill + codegen + UI). Even Phase 1
spans 3 migrations + a backfill + an aggregation endpoint + filter params +
Go/Dart codegen + accordion UI + goldens — a dedicated track, not a batch item.
The design here is the win; it makes each phase a scoped PR. Ledger §4b.
