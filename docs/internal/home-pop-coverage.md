# HOME-POP-01 — seed merch signals + populated Home golden coverage

> Discovery for `chore/home-populated-coverage`. Make the restructured Home walk-ready
> (merch signals render against seeded data) and regression-safe (the new UI gains golden
> coverage it currently lacks). **Local-verify; deploys deferred.**

## 1. Where the dev seed writes products

- The Go seeder `scripts/seed/cmd/seed/main.go` inserts from `scripts/seed/data/products.json`
  (50 SKUs). `upsertProduct` INSERTs `catalog_schema.products` with only
  `(seller_id, category_id, brand, currency, locale, status, rating_stars, rating_count)` —
  it does **not** set `free_shipping`, `is_bestseller`, or `basket_discount_pct`, so all three
  default (false / false / NULL). That's why the merch UI (#133) is dark locally.
- **Pattern for extra dev-only signals = a standalone SQL file** applied manually, exactly like
  `scripts/seed/data/coin-extras.sql` (the IA-02 Coin ledger seed; its header documents the
  `docker exec … psql < …` apply). `coin-extras.sql` is **not** run by `main.go` or `make seed`
  — it's a local walk-enabler. `scripts/dev/local-phaseb.sh` is **not in the repo** (the user's
  local harness); merch seed follows the coin-extras precedent: a committed `.sql` applied to
  postgres-ecom.
- **§3.1 plan:** `scripts/seed/data/merch-extras.sql` — deterministic `UPDATE` setting
  `is_bestseller = TRUE` on a representative subset and `basket_discount_pct` on a few
  **discounted** SKUs (overlap, so a card shows the strikethrough discount *and* the pill).
  Targeted by `variants.sku` (stable) → `product_id`. Discounted SKUs available (15): e.g.
  `MP-M002`, `MP-S002`, `MP-E003`, `MP-K004`, `MP-M004`.

## 2. How the Home goldens seed data (the ∅-coverage root)

- `mobile/test/features/home/home_goldens_5a_test.dart` (`home_{mobile_375,tablet_768,desktop_1440}`)
  overrides every Home source with **empty**: `categoriesProvider → AsyncData([])`,
  `homeMoodStoriesProvider → []`, `homeRecommendationsProvider → empty`, `flashDealsProvider → null`,
  banners empty. So `HomeCategoryRail`, `MoodStoriesStrip`, and the rails all hit their
  `roots.isEmpty / stories.isEmpty / products.isEmpty → SizedBox.shrink()` branch and render
  **nothing**. The baselines therefore capture none of the IA-01 / G-track UI → a regression in
  pucks / mood / merch flips **no** golden (confirmed empirically across PRs #130/#131/#132:
  every rebaseline reported "No golden changes to commit").

## 3. Which goldens gain coverage (decision: dedicated component goldens, not the monolith)

Re-seeding the monolithic `home_goldens_5a` fixture (categories + stories + merch rails at once)
is heavy fixture plumbing for one combined image. The **tractable, higher-signal** path is three
**dedicated component goldens**, each seeding only what it needs — directly protecting the three
new elements:

| New element | New golden | Fixture |
|---|---|---|
| Circular category pucks (G-4) | `home_category_rail_*` (new test) | `categoriesProvider` with a few root categories |
| Mood strip 72dp ring + edge-fade (G-2) | `mood_stories_strip_*` (extend existing widget test) | `homeMoodStoriesProvider` with a few stories |
| Product-card merch pills (G-3/#133) | `product_card_merch_*` (extend existing golden group) | `_card(isBestseller: true, basketDiscountPct: 15, freeShipping: true, originalPriceMinor/discountPct)` |

All use the global platform-guarded comparator (`test/flutter_test_config.dart`) → regen on
**Linux** via `golden-rebaseline.yml` (predict-then-verify); macOS only fails the platform guard.

**Predicted baselines:** purely **additive** (new `.png` + `.png.meta`), **zero flips** to existing
baselines — the new tests render new widgets the current goldens never captured. Reconciled after
the Linux regen.

## 4. Split note (§1.3 / §5) — mood-strip golden DEFER'd

§3.1 (the seed) is the walk-enabler and ships first/standalone. §3.2 ships the two **deterministic,
network-free** component goldens:

- **`product_card_merch_light`** — bestseller stamp + basket pill + free-shipping + strikethrough,
  on a null-cover card (placeholder, no network).
- **`home_category_rail`** — circular pucks via material-icon fallback (`iconUrl: null`), 4 roots +
  the "Tüm Kategoriler" entry (all fit at 375 so the lazy `ListView` builds them).

**DEFER'd: the mood-strip golden.** Unlike the product card (which guards `imageUrl == null/empty →
placeholder`, so a null cover never instantiates `CachedNetworkImage`), `MoodStoriesStrip`'s avatar
**always** instantiates `CachedNetworkImage` (`_MoodTile → ResponsiveNetworkImage`). A network URL
fires a real `HttpClient` in `flutter test` (non-deterministic + noisy unhandled-async errors that
can fail the regen). A clean mood golden needs an `HttpOverrides`/mock-image harness — fixture
plumbing beyond this PR (§5). The strip is **not coverage-naked**: its #131 widget tests already
assert the **72dp ring size** (`getSize == 72×72`) and the **edge-fade `ShaderMask`** presence.
Follow-up: add a shared golden network-image mock, then the mood (and any future image-bearing)
golden.

**Predicted baselines (additive, zero flips):** `product_card_merch_light.png(.meta)` +
`home_category_rail.png(.meta)`. No existing baseline changes (new widgets/states the current
goldens never captured). Reconciled after the Linux regen.
