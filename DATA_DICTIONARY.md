# DATA_DICTIONARY.md — Database Boundaries & Schemas v7

This file defines what data lives where and what code is allowed to read it. Crossing boundaries is forbidden, with ONE explicit exception (`ref_schema`).

Reflects PRD v6.0 (perpetual cashback) + v7 detail packs (PSP & kargo API'ları, mobil 30+ ekran, anti-fraud ML, TR e-fatura/e-arşiv/GİB).

---

## 1. Two Postgres Clusters

| Cluster | Container | Network | Used by |
|---|---|---|---|
| postgres-ecom | `postgres-ecom` | `mopro-net` | core-svc, jobs-svc |
| postgres-ledger | `postgres-ledger` | `mopro-fin-net` | fin-svc only |

NEVER:
- Connect core-svc or jobs-svc to postgres-ledger.
- Connect fin-svc to postgres-ecom.
- Open a TCP path from mopro-net to postgres-ledger.
- Run cross-cluster `dblink` or foreign-data-wrapper queries.

If core-svc needs ledger data: it asks fin-svc via Redis Streams (publish event, listen for response event) or via a thin HTTP read API exposed by fin-svc.

---

## 2. Schema-per-Module Rule

Every module owns ONE Postgres schema. Tables, types, functions belonging to the module live there.

### 2.1 postgres-ecom — Module Schemas

| Schema | Owner module | Service binary |
|---|---|---|
| `identity_schema` | identity | core-svc |
| `catalog_schema` | catalog | core-svc |
| `cart_schema` | cart | core-svc |
| `order_schema` | order | core-svc |
| `payment_schema` | payment | core-svc |
| `seller_schema` | seller | core-svc |
| `search_schema` | search | core-svc |
| `notification_schema` | notification | jobs-svc |
| `support_schema` | support | jobs-svc |
| `media_schema` | media | jobs-svc |
| `sizefinder_schema` | sizefinder | jobs-svc |

### 2.2 postgres-ledger — Module Schemas

| Schema | Owner module | Service binary |
|---|---|---|
| `wallet_schema` | wallet | fin-svc |
| `commission_schema` | commission | fin-svc |
| `sellerpayout_schema` | sellerpayout | fin-svc |
| `treasury_schema` | treasury | fin-svc |
| `cashback_schema` | cashback | fin-svc |

> `sellerpayout_schema` (seller_payouts, payout_batches, seller_psp_accounts) was
> split out of `commission_schema` by `chore/sellerpayout-schema-split` so the
> sellerpayout module owns its own schema. Cross-domain reads of commission truth
> (capture_postings) go through the `commission.CaptureRecorder` in-process seam,
> never direct SQL.

### 2.3 Schema permissions

```sql
-- One PostgreSQL ROLE per module, with USAGE/SELECT/INSERT/UPDATE/DELETE only on its own schema.
-- INSERT only on append-only ledger; UPDATE/DELETE blocked by RULES (see LEDGER_GUIDE).

REVOKE ALL ON SCHEMA public FROM PUBLIC;

CREATE ROLE identity_user LOGIN PASSWORD 'changeme';
GRANT USAGE ON SCHEMA identity_schema TO identity_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA identity_schema TO identity_user;
-- Repeat per module.
```

### 2.4 Reference Schema (postgres-ecom)

In addition to module schemas, ONE reference schema is seeded once at init and read by every module:

| Schema | Tables | Purpose |
|---|---|---|
| `ref_schema` | `currencies`, `countries`, `locales`, `categories`, `commission_rules`, `business_calendars` | Static reference data shared across modules |

`ref_schema` is read-only at runtime. Migrations under `/migrations/ecom/seed/` populate it. Modules read ref tables via SELECT (or even cross-schema JOIN — see § 3.0) but NEVER write.

### 2.5 ref_schema seed contents

```sql
-- Currencies: ISO-4217 fiat + custom coin codes
INSERT INTO ref_schema.currencies (code, kind, minor_unit_scale, symbol, name_en, active) VALUES
  ('TRY',      'fiat', 2, '₺',   'Turkish Lira',     TRUE),
  ('TRY_COIN', 'coin', 2, '₮',   'Mopro Coin',       TRUE),
  ('USD',      'fiat', 2, '$',   'US Dollar',        FALSE),
  ('EUR',      'fiat', 2, '€',   'Euro',             FALSE),
  ('AED',      'fiat', 2, 'د.إ', 'UAE Dirham',       FALSE),
  ('USD_COIN', 'coin', 2, '₮',   'Mopro Coin (USD)', FALSE),
  ('EUR_COIN', 'coin', 2, '₮',   'Mopro Coin (EUR)', FALSE),
  ('AED_COIN', 'coin', 2, '₮',   'Mopro Coin (AED)', FALSE)
ON CONFLICT DO NOTHING;

-- Countries
INSERT INTO ref_schema.countries (code, name_en, default_currency, default_locale, default_timezone) VALUES
  ('TR', 'Turkey',         'TRY', 'tr-TR', 'Europe/Istanbul'),
  ('AE', 'UAE',             'AED', 'ar-AE', 'Asia/Dubai'),
  ('DE', 'Germany',         'EUR', 'de-DE', 'Europe/Berlin'),
  ('US', 'United States',   'USD', 'en-US', 'America/New_York')
ON CONFLICT DO NOTHING;

-- Locales (BCP 47)
INSERT INTO ref_schema.locales (tag, name_en, active) VALUES
  ('tr-TR', 'Turkish (Turkey)',     TRUE),
  ('en-US', 'English (US)',         FALSE),
  ('de-DE', 'German (Germany)',     FALSE),
  ('ar-AE', 'Arabic (UAE)',         FALSE)
ON CONFLICT DO NOTHING;

-- Categories (42 launch categories with their commission rates)
INSERT INTO ref_schema.categories (id, slug, name_tr, name_en, parent_id, active) VALUES
  (1,  'aksesuar-atki-bere',          'Atkı, Bere, Eldiven, Şal ve Fular',                'Scarves, Hats, Gloves',         NULL, TRUE),
  (2,  'aksesuar-kemer-saat',         'Kemer, Saç Aksesuarı, Kravat, Kol Düğmesi, Şapka', 'Belts, Hair Accessories',       NULL, TRUE),
  (3,  'saat',                        'Saat',                                              'Watches',                       NULL, TRUE),
  (4,  'tablet-aksesuar',             'Tablet Kılıfı, Tablet Standı, Tablet Kalemi',      'Tablet Accessories',            NULL, TRUE),
  (5,  'telefon-yedek-parca',         'Batarya, Ekran, Kamera, Telefon Kasası',           'Phone Spare Parts',             NULL, TRUE),
  (6,  'oyun-konsolu',                'PlayStation 5, PlayStation 4, Xbox, Nintendo',     'Game Consoles',                 NULL, TRUE),
  (7,  'televizyon',                  'Televizyon',                                        'Television',                    NULL, TRUE),
  (8,  'bebek-emzirme',               'Emzirme Örtüsü, Emzirme Yastığı, Mama Önlüğü',     'Baby Feeding Accessories',      NULL, TRUE),
  (9,  'bebek-arabasi',               'Bebek Arabası, Puset, Oto Koltuğu, Park Yatak',    'Baby Strollers',                NULL, TRUE),
  (10, 'bebek-oyuncak',               'Çocuk ve Bebek Oyuncakları',                        'Baby Toys',                     NULL, TRUE),
  (11, 'dijital-hediye',              'Dijital Hediye Kartları (Apple, Google, Netflix)', 'Digital Gift Cards',            NULL, TRUE),
  (12, 'online-egitim',               'Online Eğitim Uygulamaları',                        'Online Education Apps',         NULL, TRUE),
  (13, 'yazilim',                     'Yazılım Ürünleri',                                  'Software Products',             NULL, TRUE),
  (14, 'beyaz-esya',                  'Bulaşık Makinesi, Buzdolabı, Çamaşır Makinesi',     'Major Appliances',              NULL, TRUE),
  (15, 'klima-kombi',                 'Klima – Kombi',                                     'AC and Boilers',                NULL, TRUE),
  (16, 'akilli-mutfak',               'Akıllı Fritöz, Akıllı Tartı, Akıllı Kettle',       'Smart Kitchen Devices',         NULL, TRUE),
  (17, 'mutfak-makineleri',           'Yiyecek ve İçecek Hazırlama, Dikiş Makinesi',      'Kitchen Machines',              NULL, TRUE),
  (18, 'taki',                        'Bijuteri & Gümüş Takı (Bileklik, Kolye, Küpe)',    'Jewelry',                       NULL, TRUE),
  (19, 'ayakkabi',                    'Ayakkabı',                                          'Shoes',                         NULL, TRUE),
  (20, 'canta',                       'Çanta',                                             'Bags',                          NULL, TRUE),
  (21, 'giyim',                       'Üst Giyim, Alt Giyim, İç Giyim, Spor Giyim',       'Clothing',                      NULL, TRUE),
  (22, 'bahce-dekor',                 'Bahçe Dekorasyonu',                                 'Garden Decoration',             NULL, TRUE),
  (23, 'havuz',                       'Havuz Ürünleri',                                    'Pool Products',                 NULL, TRUE),
  (24, 'el-aletleri',                 'El Aletleri, Elektrikli El Aletleri ve Aksesuarları','Hand Tools',                   NULL, TRUE),
  (25, 'bebek-banyo',                 'Bebek Banyo Eşyaları, Küvet, Lazımlık',            'Baby Bath Items',               NULL, TRUE),
  (26, 'kisisel-bakim',               'Epilatör, Saç Düzleştirici, Saç Maşası, Tartı',    'Personal Care',                 NULL, TRUE),
  (27, 'dizustu-bilgisayar',          'Dizüstü Bilgisayar, Oyuncu Dizüstü PC',            'Laptops',                       NULL, TRUE),
  (28, 'pc-yedek-parca',              'Bilgisayar Yedek Parça',                            'PC Components',                 NULL, TRUE),
  (29, 'projeksiyon',                 'Projeksiyon Perdesi ve Kumandaları',                'Projection Equipment',          NULL, TRUE),
  (30, 'akilli-telefon',              'Akıllı Cep Telefonu',                               'Smartphones',                   NULL, TRUE),
  (31, 'tuslu-telefon',               'Tuşlu Cep Telefonu',                                'Feature Phones',                NULL, TRUE),
  (32, 'kopek-mama',                  'Köpek Kuru Maması, Köpek Konserve Maması',         'Dog Food',                      NULL, TRUE),
  (33, 'hijyen',                      'Hasta Bezi ve Temizlik Ürünleri',                  'Hygiene Products',              NULL, TRUE),
  (34, 'aydinlatma',                  'Avize, Abajur, Aplik, Lambader, Masa Lambası',     'Lighting',                      NULL, TRUE),
  (35, 'ev-tekstili',                 'Salon, Mutfak, Yatak Odası, Bebek Tekstili',       'Home Textiles',                 NULL, TRUE),
  (36, 'parti-yilbasi',               'Parti ve Yılbaşı Ürünleri',                         'Party and New Year Products',  NULL, TRUE),
  (37, 'mutfak-gerec',                'Mutfak Gereçleri, Sofra Ürünleri, Pişirme',        'Kitchenware',                   NULL, TRUE),
  (38, 'sanat-malzeme',               'Boya Malzemeleri, Sanatsal Malzemeler',            'Art Supplies',                  NULL, TRUE),
  (39, 'kisisel-bakim-2',             'Ağız Bakım, Diş Macunu, Ağda, Cilt Bakım',         'Personal Hygiene',              NULL, TRUE),
  (40, 'oto-temizlik',                'Oto Bakım / Temizlik Ürünleri',                     'Auto Care Products',            NULL, TRUE),
  (41, 'gida',                        'Atıştırmalık, Kuru Gıda, Süt ve Kahvaltılık',      'Food Products',                 NULL, TRUE),
  (42, 'cicek',                       'Çiçek',                                              'Flowers',                       NULL, TRUE)
ON CONFLICT DO NOTHING;

-- Commission rules per market + category
-- commission_pct_bps in basis points (2000 = %20.00)
INSERT INTO ref_schema.commission_rules
  (market, category_id, commission_pct_bps, kdv_pct_bps, effective_from, active) VALUES
  ('TR', 1,  2000, 2000, now(), TRUE),  -- Atkı, Bere %20.00
  ('TR', 2,  2000, 2000, now(), TRUE),  -- Kemer, Aksesuar %20.00
  ('TR', 3,  2000, 2000, now(), TRUE),  -- Saat %20.00
  ('TR', 4,  2000, 2000, now(), TRUE),  -- Tablet aksesuar %20.00
  ('TR', 5,  2000, 2000, now(), TRUE),  -- Telefon yedek parça %20.00
  ('TR', 6,   800, 2000, now(), TRUE),  -- Oyun konsolu %8.00
  ('TR', 7,   800, 2000, now(), TRUE),  -- Televizyon %8.00
  ('TR', 8,  1650, 2000, now(), TRUE),  -- Emzirme aksesuarları %16.50
  ('TR', 9,  1650, 2000, now(), TRUE),  -- Bebek arabası %16.50
  ('TR', 10, 1650, 2000, now(), TRUE),  -- Bebek oyuncakları %16.50
  ('TR', 11,  500, 2000, now(), TRUE),  -- Dijital hediye %5.00
  ('TR', 12, 1017, 2000, now(), TRUE),  -- Online eğitim %10.17
  ('TR', 13, 1200, 2000, now(), TRUE),  -- Yazılım %12.00
  ('TR', 14, 1100, 2000, now(), TRUE),  -- Beyaz eşya %11.00
  ('TR', 15, 1100, 2000, now(), TRUE),  -- Klima/Kombi %11.00
  ('TR', 16, 1500, 2000, now(), TRUE),  -- Akıllı mutfak %15.00
  ('TR', 17, 1500, 2000, now(), TRUE),  -- Mutfak makineleri %15.00
  ('TR', 18, 2000, 2000, now(), TRUE),  -- Takı %20.00
  ('TR', 19, 2000, 2000, now(), TRUE),  -- Ayakkabı %20.00
  ('TR', 20, 2000, 2000, now(), TRUE),  -- Çanta %20.00
  ('TR', 21, 2000, 2000, now(), TRUE),  -- Giyim %20.00
  ('TR', 22, 1750, 2000, now(), TRUE),  -- Bahçe dekor %17.50
  ('TR', 23, 1750, 2000, now(), TRUE),  -- Havuz %17.50
  ('TR', 24, 1550, 2000, now(), TRUE),  -- El aletleri %15.50
  ('TR', 25, 1650, 2000, now(), TRUE),  -- Bebek banyo %16.50
  ('TR', 26, 1750, 2000, now(), TRUE),  -- Kişisel bakım %17.50
  ('TR', 27,  750, 2000, now(), TRUE),  -- Dizüstü bilgisayar %7.50
  ('TR', 28, 1550, 2000, now(), TRUE),  -- PC yedek parça %15.50
  ('TR', 29, 1600, 2000, now(), TRUE),  -- Projeksiyon %16.00
  ('TR', 30,  700, 2000, now(), TRUE),  -- Akıllı telefon %7.00
  ('TR', 31, 1000, 2000, now(), TRUE),  -- Tuşlu telefon %10.00
  ('TR', 32, 1525, 2000, now(), TRUE),  -- Köpek mama %15.25
  ('TR', 33, 1729, 2000, now(), TRUE),  -- Hijyen %17.29
  ('TR', 34, 2000, 2000, now(), TRUE),  -- Aydınlatma %20.00
  ('TR', 35, 2000, 2000, now(), TRUE),  -- Ev tekstili %20.00
  ('TR', 36, 2000, 2000, now(), TRUE),  -- Parti/Yılbaşı %20.00
  ('TR', 37, 1932, 2000, now(), TRUE),  -- Mutfak gereç %19.32
  ('TR', 38, 1678, 2000, now(), TRUE),  -- Sanat malzeme %16.78
  ('TR', 39, 1678, 2000, now(), TRUE),  -- Kişisel hijyen %16.78
  ('TR', 40, 1650, 2000, now(), TRUE),  -- Oto temizlik %16.50
  ('TR', 41, 1525, 2000, now(), TRUE),  -- Gıda %15.25
  ('TR', 42, 2000, 2000, now(), TRUE)   -- Çiçek %20.00
ON CONFLICT DO NOTHING;

-- Business calendars (per market) for AddBusinessDays calculation.
-- Each row is a single non-business date (weekend or holiday).
-- TR launch seed: 2026-2030 official Turkish public holidays.
CREATE TABLE IF NOT EXISTS ref_schema.business_calendars (
  market TEXT NOT NULL,
  date DATE NOT NULL,
  reason TEXT NOT NULL,
  PRIMARY KEY (market, date)
);

-- Examples (subset; full seed lives in /migrations/ecom/seed/0010_business_calendars_tr.sql):
INSERT INTO ref_schema.business_calendars (market, date, reason) VALUES
  ('TR', '2026-01-01', 'Yılbaşı'),
  ('TR', '2026-04-23', 'Ulusal Egemenlik ve Çocuk Bayramı'),
  ('TR', '2026-05-01', 'Emek ve Dayanışma Günü'),
  ('TR', '2026-05-19', 'Atatürk''ü Anma Gençlik ve Spor Bayramı'),
  ('TR', '2026-07-15', 'Demokrasi ve Milli Birlik Günü'),
  ('TR', '2026-08-30', 'Zafer Bayramı'),
  ('TR', '2026-10-29', 'Cumhuriyet Bayramı')
ON CONFLICT DO NOTHING;
```

`commission_pct_bps` is basis points (10000 = 100%). `kdv_pct_bps` is the VAT rate at sale time (2000 = %20 as of May 2026).

NOTE v5 KEY DESIGN: there is NO `cashback_rules` table because the cashback formula is **deterministically derived** from `commission_pct_bps` (cashback_total = commission, monthly = total / 24, fixed). The cashback engine reads `commission_pct_bps` from the snapshot in `order_items` (set at order time from `ref_schema.commission_rules`).

---

## 3. Cross-Schema Query Ban

The most important rule in this file:

> **No SQL JOIN across module schemas. No `FROM <other_module>_schema.table`. No FOREIGN KEY across module schemas.**

### 3.0 ref_schema is the ONE Exception

`ref_schema.currencies`, `ref_schema.countries`, `ref_schema.locales`, `ref_schema.categories`, `ref_schema.commission_rules`, `ref_schema.business_calendars` are READABLE by every module via direct SELECT or JOIN. They are universal vocabulary; cross-schema is intentional here.

Writing to `ref_schema` is forbidden at runtime; only seed migrations populate it.

Example allowed:
```sql
SELECT v.price_minor, v.price_currency, c.symbol
FROM catalog_schema.variants v
JOIN ref_schema.currencies c ON c.code = v.price_currency
WHERE v.id = $1;

-- catalog reads commission to display in seller panel
SELECT cr.commission_pct_bps, cr.kdv_pct_bps
FROM ref_schema.commission_rules cr
WHERE cr.market = $1 AND cr.category_id = $2 AND cr.active = TRUE;
```

### 3.1 Allowed (own schema only)

```sql
SELECT * FROM order_schema.orders WHERE id = $1;
```

### 3.2 Forbidden

```sql
-- Cross-module-schema JOIN
SELECT o.*, p.title
FROM order_schema.orders o
JOIN catalog_schema.products p ON p.id = o.product_id;

-- Cross-module-schema lookup
SELECT title FROM catalog_schema.products WHERE id = ?
-- (when called from order code)

-- Cross-module-schema FK
ALTER TABLE order_schema.orders
    ADD CONSTRAINT fk_product
    FOREIGN KEY (product_id) REFERENCES catalog_schema.products(id);
```

### 3.3 The right way

If `order` needs the product title, it calls `catalog.GetByID(ctx, id)` (in-memory function call inside core-svc), or stores a denormalized snapshot at order creation time.

### 3.4 Enforcement

- `golangci-lint depguard`: `internal/order/*.go` cannot import `internal/catalog/repository`. It can only import `internal/catalog` (the public interface).
- `scripts/check-module-boundaries.sh` greps for `FROM <other>_schema.` patterns in raw SQL files (excluding `ref_schema`).

---

## 4. PII Handling — AES-GCM Envelope Encryption

### 4.1 PII fields (must be encrypted at rest)

```
identity_schema.users.national_id              (encrypted; format per national_id_country)
identity_schema.users.national_id_country      (ISO-3166 alpha-2; e.g., 'TR', 'DE', 'AE')
identity_schema.users.phone_e164               (encrypted; always E.164 international format)
identity_schema.users.email                    (encrypted)
identity_schema.users.locale                   (BCP 47 language tag; e.g., 'tr-TR', 'en-US')
identity_schema.users.timezone                 (IANA TZ; e.g., 'Europe/Istanbul', 'UTC')

identity_schema.user_addresses.recipient_name  (encrypted)
identity_schema.user_addresses.street_line1    (encrypted)
identity_schema.user_addresses.street_line2    (encrypted, optional)
identity_schema.user_addresses.city
identity_schema.user_addresses.region          (state/province, optional; required in US/CA)
identity_schema.user_addresses.postal_code     (format per country; validated against ref_schema.countries)
identity_schema.user_addresses.country_code    (ISO-3166 alpha-2; joinable to ref_schema.countries)
identity_schema.user_addresses.phone_e164      (encrypted)

support_schema.tickets.user_message            (encrypted; free-text from users may contain PII)

seller_schema.sellers.tax_id                   (encrypted; tax/VAT number)
seller_schema.sellers.iban                     (encrypted; bank account)
seller_schema.sellers.bank_account_holder_name (encrypted)
```

### 4.2 Mechanism

- A master key (KEK) lives in `.env` (`PII_KEK_BASE64`). Rotated every 90 days.
- Each row gets a fresh 256-bit DEK (data encryption key), AES-GCM, 96-bit nonce.
- Stored format: `<nonce>:<ciphertext>:<dek_encrypted_with_kek>`.
- Hashed lookup column: `<column>_hash = SHA256(value || pepper)`.

### 4.3 Code helper (mandatory)

```go
// /pkg/crypto/pii.go
package crypto

func EncryptPII(kek []byte, plaintext []byte) (string, error) { /* AES-GCM envelope */ }
func DecryptPII(kek []byte, ciphertext string) ([]byte, error) { /* AES-GCM envelope */ }
func HashLookup(value string, pepper []byte) string { /* SHA256(value || pepper) */ }
```

NEVER write plaintext PII to logs. NEVER `SELECT *` PII columns to display.

---

## 5. Migration Rules

### 5.1 File path

`/migrations/<ecom|ledger>/<NNNN>_<verb>_<noun>.sql`

Numeric prefix is monotonically increasing. Never re-use numbers.

### 5.2 Allowed operations

- `CREATE TABLE`
- `ALTER TABLE ADD COLUMN` (nullable or with DEFAULT that does not require rewrite)
- `CREATE INDEX CONCURRENTLY`
- `CREATE OR REPLACE VIEW`
- `CREATE FUNCTION`
- `INSERT` (seeding reference data only, idempotent with `ON CONFLICT DO NOTHING`)

### 5.3 FORBIDDEN destructive operations

```sql
-- ❌ DROP TABLE
DROP TABLE catalog_schema.deprecated_table;

-- ❌ DROP COLUMN
ALTER TABLE order_schema.orders DROP COLUMN legacy_status;

-- ❌ ALTER COLUMN TYPE (rewrites the table)
ALTER TABLE catalog_schema.products ALTER COLUMN price_minor TYPE BIGINT;

-- ❌ ALTER ... SET NOT NULL on populated table
ALTER TABLE catalog_schema.products ALTER COLUMN brand_id SET NOT NULL;

-- ❌ DROP INDEX (on production-grade table) without CONCURRENTLY
DROP INDEX order_schema.orders_status_idx;

-- ❌ Renames
ALTER TABLE order_schema.orders RENAME COLUMN status TO order_status;
```

### 5.4 Expand-and-Contract

To replace a column without DROP:

1. **Expand:** add the new column. Both writers populate old + new.
2. **Backfill:** a job copies old → new for historical rows.
3. **Switch:** readers read from new. Old column becomes unused.
4. **Contract:** ONLY after ≥ 30 days, with explicit human approval, schedule a `DROP COLUMN` in a staged maintenance window.

The Contract step is OUT OF SCOPE for autonomous agent action. Agents propose, humans execute.

### 5.5 Ledger has STRICTER rules

In `postgres-ledger`:
- NEVER drop or rename anything.
- NEVER alter a column type once it carries production data.
- New tables/columns are append-only.
- `cashback_schema.plans` rows are IMMUTABLE once created. Mutations to core fields forbidden by trigger.
- `sellerpayout_schema.seller_payouts` rows are IMMUTABLE once created. Status transitions only via INSERT into a separate audit table.

If a ledger schema change is genuinely needed, write a NEW schema/table in parallel; never mutate existing.

### 5.6 Currency and Reference Tables

- `ref_schema.currencies` rows have immutable shape. Adding a new currency is an INSERT (and a corresponding chart-of-accounts seed). Renaming or removing a currency is FORBIDDEN.
- Adding a new country, locale, category, commission rule, or business calendar entry follows the same INSERT-only pattern.
- Updating a `commission_rules` row applies ONLY to NEW orders going forward (snapshot in `order_items.commission_pct_bps` insulates historical orders). Use `effective_from` + `effective_to` columns; never UPDATE in place.
- All amount columns in any schema MUST have an accompanying currency column or reference a row whose currency is implicit (e.g., an account row).
- The constraint: any monetary value in the database is joinable to `ref_schema.currencies.code`. NO "naked" amounts.

### 5.7 Cashback & Seller Payout Schema Specific Rules — v6 LOCKED PERPETUAL

- `cashback_schema.plans.monthly_amount_minor` is COMPUTED at insert and IMMUTABLE.
- `cashback_schema.plans.reference_interest_rate_bps` is snapshotted at insert (default 5000 = %50) and IMMUTABLE.
- v6: NO `total_amount_minor`, NO `total_months`, NO `end_date` columns. Plan is PERPETUAL.
- `cashback_schema.plans.start_date` (first instalment date) is `delivered_at + 3 business days` and IMMUTABLE.
- `cashback_schema.payments` rows are append-only; one row per `(plan_id, period_yyyymm)` created by the monthly cron.
- A trigger enforces: a payment's `(plan_id, period_yyyymm)` is UNIQUE.
- `sellerpayout_schema.seller_payouts.unlock_at` is `delivered_at + 3 business days` and IMMUTABLE.
- `sellerpayout_schema.seller_payouts.amount_minor` is the snapshotted net amount, IMMUTABLE.

---

## 6. Catalog Tables (Multi-Currency, Multi-Language, Category-Aware)

```sql
CREATE TABLE catalog_schema.products (
  id BIGSERIAL PRIMARY KEY,
  seller_id BIGINT NOT NULL,
  category_id BIGINT NOT NULL,                 -- references ref_schema.categories(id), enforced via app code
  brand TEXT NOT NULL DEFAULT '',
  default_currency TEXT NOT NULL DEFAULT 'TRY',-- joinable to ref_schema.currencies(code)
  default_locale TEXT NOT NULL DEFAULT 'tr-TR',-- joinable to ref_schema.locales(tag)
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE catalog_schema.product_translations (
  product_id BIGINT NOT NULL REFERENCES catalog_schema.products(id),
  locale TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (product_id, locale)
);

CREATE TABLE catalog_schema.variants (
  id BIGSERIAL PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES catalog_schema.products(id),
  sku TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '',
  size TEXT NOT NULL DEFAULT '',
  price_minor BIGINT NOT NULL CHECK (price_minor >= 0),
  price_currency TEXT NOT NULL DEFAULT 'TRY', -- joinable to ref_schema.currencies(code)
  stock INTEGER NOT NULL DEFAULT 0,
  image_keys TEXT[] NOT NULL DEFAULT '{}'::text[]
);
CREATE UNIQUE INDEX variants_product_sku_uq ON catalog_schema.variants(product_id, sku);
```

The seller panel displays the cashback preview ("alıcı her ay X.XX coin alacak — süresiz") by reading `ref_schema.commission_rules` for the selected category and applying the v6 formula: `monthly = (price × commission_pct × 0.50) / 12`.

---

## 7. Order Tables (Multi-Currency, Trendyol-style Shipping, Commission Snapshot)

```sql
CREATE TABLE order_schema.orders (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  status TEXT NOT NULL CHECK (status IN
    ('pending_payment','paid','shipped','delivered','cancelled','refunded','partially_refunded')),
  subtotal_minor BIGINT NOT NULL CHECK (subtotal_minor >= 0),
  shipping_minor BIGINT NOT NULL DEFAULT 0,
  shipping_payer TEXT NOT NULL CHECK (shipping_payer IN ('buyer','seller','split','threshold_free')),
  total_minor BIGINT NOT NULL CHECK (total_minor >= 0),       -- subtotal + shipping (if buyer pays)
  currency TEXT NOT NULL,                                     -- single currency per order
  market TEXT NOT NULL DEFAULT 'TR',                          -- ISO-3166 alpha-2
  delivered_at TIMESTAMPTZ,                                   -- set when kargo webhook reports delivered
  cashback_eligible BOOLEAN NOT NULL DEFAULT TRUE,
  cashback_currency TEXT NOT NULL DEFAULT 'TRY_COIN',
  -- v6: cashback is perpetual; aylık coin computed from order_items.commission_amount_minor × ref_rate / 12
  --     stored on the plan, not on the order (single source of truth lives on plans.monthly_amount_minor)
  idempotency_key TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE order_schema.order_items (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES order_schema.orders(id),
  variant_id BIGINT NOT NULL,
  seller_id BIGINT NOT NULL,
  category_id BIGINT NOT NULL,                                -- snapshot for commission calculation
  qty INTEGER NOT NULL CHECK (qty > 0),
  unit_price_minor BIGINT NOT NULL CHECK (unit_price_minor >= 0),
  unit_price_currency TEXT NOT NULL,                          -- always equals order.currency
  -- v5 SNAPSHOTS taken at order time from ref_schema.commission_rules:
  commission_pct_bps INTEGER NOT NULL,                        -- e.g., 2000 for %20.00
  kdv_pct_bps INTEGER NOT NULL,                               -- e.g., 2000 for %20.00 KDV
  commission_amount_minor BIGINT NOT NULL,                    -- = unit_price * qty * commission_pct_bps / 10000
  kdv_amount_minor BIGINT NOT NULL,                           -- = commission_amount_minor * kdv_pct_bps / 10000
  seller_net_minor BIGINT NOT NULL                            -- = unit_price * qty - commission - kdv
);

CREATE INDEX CONCURRENTLY orders_user_idx ON order_schema.orders(user_id, created_at DESC);
CREATE INDEX CONCURRENTLY orders_status_idx ON order_schema.orders(status);
CREATE INDEX CONCURRENTLY orders_delivered_idx ON order_schema.orders(delivered_at)
    WHERE delivered_at IS NOT NULL;
```

The snapshots in `order_items` are the single source of truth for commission, KDV, and seller net calculations. Both the cashback engine and the seller payout engine read these snapshots; they never recompute from `ref_schema.commission_rules` because rates may have changed between order time and event consumption.

---

## 8. Cashback Schema Tables (postgres-ledger / cashback_schema) — v6 PERPETUAL

```sql
-- v6 PERPETUAL: NO `rules` table, NO `total_amount`, NO `total_months`, NO `end_date`.
-- The cashback formula is fully derived from order_items snapshot + frozen reference_interest_rate.
-- Plan is open-ended — pays monthly_amount_minor every month forever until cancellation.

CREATE TABLE cashback_schema.plans (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL,                                              -- denormalized; no FK across cluster
  user_id BIGINT NOT NULL,
  monthly_amount_minor BIGINT NOT NULL CHECK (monthly_amount_minor > 0), -- v6: aylık coin (sabit, dondurulmuş)
  currency TEXT NOT NULL DEFAULT 'TRY_COIN',
  reference_interest_rate_bps INTEGER NOT NULL DEFAULT 5000              -- v6: %50.00 = 5000 bps (snapshotted)
    CHECK (reference_interest_rate_bps BETWEEN 1 AND 20000),
  -- monthly_amount_minor = sum(order_items.commission_amount_minor) × reference_interest_rate_bps / 10000 / 12
  start_date DATE NOT NULL,                                              -- = delivered_at + 3 business days
  -- NO end_date — plan is perpetual.
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','cancelled','suspended')),
  delivered_at TIMESTAMPTZ NOT NULL,                                     -- snapshot of order delivered timestamp
  market TEXT NOT NULL DEFAULT 'TR',
  commission_snapshot JSONB NOT NULL,                                    -- per-item commission breakdown (audit)
  idempotency_key TEXT NOT NULL UNIQUE,                                  -- format: 'cashback:plan:order_<order_id>'
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX cashback_plans_user_idx ON cashback_schema.plans(user_id, status);
CREATE INDEX cashback_plans_order_idx ON cashback_schema.plans(order_id);
CREATE INDEX cashback_plans_active_due_idx ON cashback_schema.plans(start_date)
  WHERE status='active';

-- Trigger: plans rows are IMMUTABLE except for status field (and monthly_amount on partial refund via audit-logged CLI).
CREATE OR REPLACE FUNCTION cashback_schema.enforce_plan_immutable()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.monthly_amount_minor != NEW.monthly_amount_minor THEN
        -- Allow only when accompanied by an entry in plans_history (partial refund audit trail)
        IF NOT EXISTS (
            SELECT 1 FROM cashback_schema.plans_history
            WHERE plan_id = OLD.id AND created_at > now() - interval '2 seconds'
        ) THEN
            RAISE EXCEPTION 'monthly_amount_minor mutation requires plans_history entry (partial refund only)';
        END IF;
    END IF;
    IF OLD.start_date != NEW.start_date
       OR OLD.currency != NEW.currency
       OR OLD.reference_interest_rate_bps != NEW.reference_interest_rate_bps
       OR OLD.delivered_at != NEW.delivered_at
       OR OLD.order_id != NEW.order_id THEN
        RAISE EXCEPTION 'cashback plan core fields are immutable';
    END IF;
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER cashback_plan_immutable_trg
BEFORE UPDATE ON cashback_schema.plans
FOR EACH ROW EXECUTE FUNCTION cashback_schema.enforce_plan_immutable();

-- Audit table for partial refunds (tracks every monthly_amount_minor change)
CREATE TABLE cashback_schema.plans_history (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES cashback_schema.plans(id),
  field_changed TEXT NOT NULL,
  old_value TEXT NOT NULL,
  new_value TEXT NOT NULL,
  reason TEXT NOT NULL,
  changed_by TEXT NOT NULL,                                              -- 'cli:partial-refund', 'admin', etc.
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- v6: payments tablosu açık-uçlu; aylık cron her ay aktif planlar için TEK row INSERT eder.
-- Önceden 24 satır seedlemeyiz; perpetual model.
CREATE TABLE cashback_schema.payments (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES cashback_schema.plans(id),
  period_yyyymm INTEGER NOT NULL                                         -- v6: month_index yerine 202607 gibi
    CHECK (period_yyyymm BETWEEN 202600 AND 209912),
  scheduled_date DATE NOT NULL,
  paid_date DATE,
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','paid','failed','cancelled')),
  ledger_transaction_id BIGINT,                                          -- references wallet_schema.transactions(id) when paid
  idempotency_key TEXT NOT NULL UNIQUE,                                  -- format: 'cashback:plan_<id>:period_<yyyymm>'
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_attempt_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX cashback_payments_plan_period_uq ON cashback_schema.payments(plan_id, period_yyyymm);
CREATE INDEX cashback_payments_due_idx ON cashback_schema.payments(scheduled_date, status)
    WHERE status = 'scheduled';
```

---

## 9. Seller Payout Schema Tables (postgres-ledger / sellerpayout_schema) — NEW IN v5

```sql
CREATE TABLE sellerpayout_schema.seller_payouts (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL,                                   -- denormalized; no FK across cluster
  seller_id BIGINT NOT NULL,
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),      -- snapshotted seller_net_minor sum
  currency TEXT NOT NULL DEFAULT 'TRY',
  delivered_at TIMESTAMPTZ NOT NULL,                          -- when kargo confirmed delivered
  unlock_at DATE NOT NULL,                                    -- = delivered_at + 3 business days
  paid_at TIMESTAMPTZ,                                        -- when PSP transfer completed
  psp_transfer_id TEXT,                                       -- provider's transfer reference
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN
    ('scheduled','processing','paid','failed','cancelled','reversed')),
  market TEXT NOT NULL DEFAULT 'TR',
  ledger_transaction_id BIGINT,                               -- set when ledger move completes
  idempotency_key TEXT NOT NULL UNIQUE,                       -- format: 'payout:order_<order_id>:seller_<seller_id>'
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_attempt_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX seller_payouts_due_idx ON sellerpayout_schema.seller_payouts(unlock_at, status)
    WHERE status = 'scheduled';
CREATE INDEX seller_payouts_seller_idx ON sellerpayout_schema.seller_payouts(seller_id, created_at DESC);
CREATE INDEX seller_payouts_order_idx ON sellerpayout_schema.seller_payouts(order_id);

-- Trigger: payout rows are IMMUTABLE for amount and unlock_at.
CREATE OR REPLACE FUNCTION sellerpayout_schema.enforce_payout_immutable()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.amount_minor != NEW.amount_minor
       OR OLD.unlock_at != NEW.unlock_at
       OR OLD.currency != NEW.currency
       OR OLD.order_id != NEW.order_id
       OR OLD.seller_id != NEW.seller_id THEN
        RAISE EXCEPTION 'seller_payout core fields are immutable; create reversal instead';
    END IF;
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER seller_payout_immutable_trg
BEFORE UPDATE ON sellerpayout_schema.seller_payouts
FOR EACH ROW EXECUTE FUNCTION sellerpayout_schema.enforce_payout_immutable();
```

---

## 10. Quick Reference for Agents

When generating SQL or migrations:

| Question | Answer |
|---|---|
| Which DB? | The one matching the module's binary (see § 1) |
| Which schema? | The one belonging to the module |
| Cross-schema JOIN? | NEVER, except `ref_schema` |
| Drop or rename? | NEVER (use expand-and-contract) |
| Money type? | `BIGINT` minor units + currency column |
| PII column? | Encrypted via `crypto.EncryptPII`; add `_hash` column for lookups |
| Idempotency? | UNIQUE constraint on the natural key |
| Index? | `CREATE INDEX CONCURRENTLY` always |
| Connection? | Through PgBouncer; never direct to Postgres |
| FK across schemas? | NEVER (denormalize the reference) |
| Cashback plan mutation? | NEVER (create reversal/new plan) |
| Seller payout mutation? | NEVER (create reversal) |
| Currency hardcode? | NEVER (read from config or ref_schema) |
| Commission percent hardcode? | NEVER (read from snapshot in `order_items.commission_pct_bps`) |
| Switch from perpetual to fixed-term cashback? | NEVER (v6 model; ADR + new constitution required) |
| `reference_interest_rate_bps` change for existing plan? | NEVER (snapshotted at creation; only NEW plans can use a different rate, after CFO ADR) |
| 3 business day delay change? | NEVER (read business_calendars + AddBusinessDays) |
| Mixed-currency transaction? | NEVER (separate FX transactions) |

---

## 11. e-Fatura / e-Arşiv Schema (postgres-ecom / einvoice_schema) — v7 NEW

GİB üzerinden Foriba (veya alternatif Bulut e-Fatura sağlayıcı) entegrasyonu için tablolar.

```sql
CREATE SCHEMA einvoice_schema AUTHORIZATION einvoice_user;

CREATE TABLE einvoice_schema.invoices (
  id BIGSERIAL PRIMARY KEY,
  -- Mopro'nun kestiği faturalar (komisyon Mopro→satıcı, satış Mopro→tüketici Phase 5+)
  type TEXT NOT NULL CHECK (type IN ('commission', 'sale', 'refund_credit_note', 'monthly_summary')),
  order_id BIGINT,                                    -- nullable (monthly_summary için NULL)
  seller_id BIGINT,                                   -- commission/monthly_summary için doludur
  buyer_user_id BIGINT,                               -- sale türünde
  
  -- Fatura tutarları
  amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),  -- KDV hariç
  kdv_minor BIGINT NOT NULL CHECK (kdv_minor >= 0),
  total_minor BIGINT NOT NULL CHECK (total_minor >= 0),    -- amount + kdv
  currency TEXT NOT NULL DEFAULT 'TRY',
  
  -- GİB / Foriba referansları
  invoice_kind TEXT NOT NULL CHECK (invoice_kind IN ('e_fatura', 'e_arsiv')),
  ettn TEXT UNIQUE,                                   -- Elektronik Tebligat Takip Numarası (GİB tarafından)
  foriba_invoice_id TEXT UNIQUE,                      -- Foriba iç ID
  foriba_uuid TEXT,                                   -- UBL-TR UUID
  invoice_number TEXT,                                -- "MPS2026000000001" format (yıl + sıra)
  invoice_date DATE NOT NULL,
  
  -- XML & arşiv
  raw_xml_b2_key TEXT,                                -- Backblaze B2'deki UBL-TR XML
  pdf_b2_key TEXT,                                    -- okunaklı PDF
  
  -- Durum
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','queued','sent','delivered','rejected','cancelled')),
  rejection_reason TEXT,                              -- GİB ret durumunda
  
  -- Vergi mükellef bilgileri (snapshot)
  issuer_vkn TEXT NOT NULL,                           -- Mopro VKN (10 hane)
  recipient_vkn TEXT,                                 -- e-fatura için satıcı VKN
  recipient_tckn TEXT,                                -- e-arşiv (B2C) için TC kimlik (encrypted)
  recipient_title TEXT NOT NULL,                      -- ünvan/ad-soyad
  recipient_address TEXT NOT NULL,
  recipient_email TEXT,                               -- e-arşiv için
  
  idempotency_key TEXT NOT NULL UNIQUE,               -- 'einvoice:order_<id>:type_<t>' format
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX einvoice_status_idx ON einvoice_schema.invoices(status, created_at)
  WHERE status IN ('pending','queued','rejected');
CREATE INDEX einvoice_order_idx ON einvoice_schema.invoices(order_id);
CREATE INDEX einvoice_seller_idx ON einvoice_schema.invoices(seller_id, invoice_date DESC);
CREATE INDEX einvoice_ettn_idx ON einvoice_schema.invoices(ettn) WHERE ettn IS NOT NULL;

-- Audit trail of state transitions
CREATE TABLE einvoice_schema.invoice_history (
  id BIGSERIAL PRIMARY KEY,
  invoice_id BIGINT NOT NULL REFERENCES einvoice_schema.invoices(id),
  old_status TEXT,
  new_status TEXT NOT NULL,
  reason TEXT,
  raw_response JSONB,                                 -- Foriba/GİB raw response
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Mopro kayıtlı seri numarası takibi (TR mevzuat: sıralı, atlamasız)
CREATE TABLE einvoice_schema.invoice_sequences (
  year INTEGER NOT NULL,
  invoice_kind TEXT NOT NULL CHECK (invoice_kind IN ('e_fatura', 'e_arsiv')),
  next_number BIGINT NOT NULL DEFAULT 1,
  PRIMARY KEY (year, invoice_kind)
);

-- Aylık KDV beyannamesi takibi (her ayın 26'sında verilmesi gerekir)
CREATE TABLE einvoice_schema.kdv_declarations (
  id BIGSERIAL PRIMARY KEY,
  period_yyyymm INTEGER NOT NULL UNIQUE,
  total_invoiced_minor BIGINT NOT NULL,
  total_kdv_collected_minor BIGINT NOT NULL,
  total_kdv_paid_minor BIGINT NOT NULL DEFAULT 0,    -- Mopro'nun gider KDV'si
  net_kdv_due_minor BIGINT NOT NULL,                 -- collected - paid
  declaration_status TEXT DEFAULT 'pending'
    CHECK (declaration_status IN ('pending','submitted','accepted','rejected')),
  submitted_at TIMESTAMPTZ,
  gib_reference TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**KDV beyanı:** Her ayın 26'sında otomatik cron `kdv_declarations` tablosunu o ayın özetiyle doldurur; muhasebeci/CFO Foriba arayüzünden imzalı beyan gönderir. Mali müşavirin Mopro adına imza yetkisi olmalı (Phase 0 vekaletname).

**Hukuki:** Mopro VKN almak zorunda; KEP adresi gerekli (PTT KEP ~700 TL/yıl); 5M TL+ ciro eşiği aşılınca e-fatura mükellefi otomatik (öncesi gönüllü mükellef olunmalı çünkü marketplace operatörü).

---

**End of DATA_DICTIONARY.md.** See LEDGER_GUIDE.md for ledger and cashback business rules.
