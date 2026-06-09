# PLP-SEED — category density for the filter walk — discovery

> The PLP filter walk needs one category dense + facet-varied enough that every
> filter has something to act on. Verified on `chore/plp-seed-density`.

## How the PLP scopes products to a category → **Outcome B (no rollup)**

- `filtered_products_provider` → `api.listProducts(categoryId: …)` →
  `internal/catalog/repository.go:373`:
  ```sql
  AND p.category_id = $N        -- EXACT match, no descendants
  ```
- **No subtree rollup.** The recursive CTE (`repository.go:273`) builds the
  category *tree listing* (depth), **not** product scoping. A parent/root
  category PLP therefore shows only products assigned to that *exact* id.
- In the seed, products sit on **leaf** categories, so the **6 root categories
  (`root-elektronik` …) have ZERO direct products** → their PLP is empty.
  **This is a real parity finding** (Trendyol rolls a category's subtree up).
  Recorded as **PLP-12** in the audit; **not built here** (§1.2 / Outcome C).

## Current per-category density

- `scripts/seed/data/products.json`: **50 products across ~30 leaf categories →
  2–3 products each** (max 3). Globally rich (**25 brands**, price **₺89–
  ₺89,999**) but **per leaf category there's almost nothing to filter**.
- Two more facet gaps in the base seed (independent of density):
  - **All ratings are 3.9–4.9** → the rating buckets (2+/3+/4+) can't distinguish.
  - **`free_shipping` is never set TRUE** (migration 0081 default FALSE; no seed
    flips it) → the free-shipping filter is vacuous.
  - (`is_bestseller` / `basket_discount_pct` ARE flipped on a few SKUs by
    `merch-extras.sql` — those two facets work once that's applied.)

## Seed mechanism (how extras are applied)

- `make seed` (Makefile `build-seed` + CLI) loads `categories.json` +
  `products.json` only. `main.go` does **not** glob `data/*.sql`.
- **Extras SQL (`merch-extras.sql`, `coin-extras.sql`) are applied MANUALLY**
  via `docker exec -i postgres-ecom psql … < file.sql` (per each file's header).
- **Discovery shift:** the prompt's `scripts/dev/local-phaseb.sh` **does not
  exist** — there is no such script; the manual-psql apply is the real path.
- Categories live in **`ref_schema.categories`** (slug-keyed; CLAUDE.md shared
  ref schema), products in `catalog_schema.products` (FK `category_id`).

## Plan (Outcome B + C-note) — chosen walk category: `elektr-kea`

New dev-only idempotent `scripts/seed/data/plp-density-extras.sql` mirroring
`merch-extras.sql` (UPDATEs keyed on stable `variants.sku`, never fabricates):

1. **Re-point ~28 existing SKUs** into **`elektr-kea`** ("Küçük Ev Aletleri") —
   spanning **~23 brands** (exercises the searchable list + show-more >8), the
   full **₺89–₺89,999** price spread, several discounts, and the bestseller /
   basket-discount SKUs already flagged by `merch-extras.sql`.
2. **Spread 5 ratings** down to 2.4–3.6 so the **2+/3+/4+ buckets** each select a
   distinct subset.
3. **Set `free_shipping = TRUE`** on 8 of them so that filter has options.

> **Deliberately brand-incoherent** (a book/cosmetic/appliance mix under one
> leaf): a **dev test fixture** for filter mechanics, not a realistic catalog,
> local-only. Re-running `make seed` resets it.

**Apply (after `make seed` + `merch-extras.sql`):**
`docker exec -i postgres-ecom psql -v ON_ERROR_STOP=1 -U ecom_admin -d mopro_ecom < scripts/seed/data/plp-density-extras.sql`
then walk **`/categories/<elektr-kea id>`** — ~28 products, every facet populated.
