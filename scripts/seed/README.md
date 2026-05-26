# Catalog Seed

Idempotent seed script that populates `ref_schema.categories`, `ref_schema.commission_rules`, and `catalog_schema` with realistic Turkish-market data.

## Prerequisites

1. Migrations applied through `0061_catalog_seed_fields` (adds `discount_price_minor`, `rating_stars`, `rating_count`, `specs`, global SKU unique index).
2. A reachable `postgres-ecom` instance.

## Quick start

```bash
# Dry-run: see what would change, write nothing.
make seed-dry-run DATABASE_URL="postgres://ecom_app:pass@localhost:5432/mopro_ecom?sslmode=disable"

# Seed staging:
STAGING_DATABASE_URL="postgres://..." make seed-staging

# Seed production (requires explicit confirmation):
SEED_PROD=yes PROD_DATABASE_URL="postgres://..." make seed-prod
```

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--db-url` | `$DATABASE_URL` | PostgreSQL connection string |
| `--data-dir` | `scripts/seed/data` | Directory with JSON files |
| `--dry-run` | `false` | Print plan, no writes |
| `--scope` | `all` | `all` \| `categories` \| `products` |
| `--seller-id` | `1` | Seller ID assigned to seeded products |
| `--market` | `TR` | Market code for commission rules |
| `--force` | `false` | Overwrite even if record looks identical |

## Data files

| File | Description |
|------|-------------|
| `data/categories.json` | 31 hierarchical categories (IDs 101–131): 6 root + 25 leaf |
| `data/brands.json` | 30 reference brand names used by products |
| `data/products.json` | 50 products — 1 variant each, globally unique SKU `MP-*` |

### Category IDs

Categories are inserted with explicit IDs starting at **101** to avoid conflicts with the 42 flat categories already seeded by `deploy/postgres-ecom/init/50-ref-seed.sql` (IDs 1–42).

### Cashback validation

Every product in `products.json` carries a `cashback_total_months` field. Before any write the runner verifies:

```
cashback_total_months == CashbackK(156000) / category.commission_pct_bps   (integer division)
```

The seed aborts if any product fails this check, so the formula constant always stays in sync with `internal/cashback/calculator.go`.

### Product distribution

| Dimension | Requirement | Count |
|-----------|-------------|-------|
| Price | Under ₺500 | 5 |
| Price | ₺500 – ₺2 500 | 20 |
| Price | ₺2 500 – ₺10 000 | 15 |
| Price | Above ₺10 000 | 10 |
| Discount | Has `discount_price_minor` | 15 |
| Stock | Zero (`stock_qty = 0`) | 10 |
| Stock | Low (1–4) | 5 |
| Stock | Normal (5+) | 35 |
| Ratings | `rating_count > 1000` | 5 |
| Coverage | ≥5 products per root category | 6 × 5 = 30 min |

## Idempotency

Re-running the seed with identical data produces **0 inserts, 0 updates** (rows exist, UPDATE is a no-op at the DB level because values are identical). Using `--force` makes the runner issue UPDATEs regardless.

## Extending the seed

1. Add entries to the JSON files.  
2. Run `make seed-dry-run` to preview.  
3. Run `make seed-staging` to apply.  
4. Commit both the JSON changes and the new migration (if schema changed).
