# GEN-SYNC — stale `mopro_api` deserializer + the codegen-drift gap

> Fix the stale committed `*.g.dart` in `mopro_api` (the merch fields didn't
> deserialize → the shipped UI didn't render in real use) **and** close the CI gap
> that let it drift. Verified on `fix/mopro-api-gen-sync`.

## The bug (confirmed)

`mobile/packages/mopro_api/lib/src/model/product_summary.g.dart` (committed on
`main`) does **not** deserialize `isBestseller` / `basketDiscountPct`, although the
hand-written model (`product_summary.dart`) declares them. So
`ProductSummary.fromJson` silently produced `isBestseller = false` /
`basketDiscountPct = null` on the **real API path** → the shipped "Çok Satan"
stamp + "Sepette %X" pill **never rendered in production**. Widget tests construct
`ProductSummary` directly (bypassing `fromJson`), so they passed — the gap was
invisible to the suite.

After `dart run build_runner build` in the package, `product_summary.g.dart` gains:
```dart
isBestseller: $checkedConvert('is_bestseller', (v) => v as bool? ?? false),
basketDiscountPct: $checkedConvert('basket_discount_pct', (v) => (v as num?)?.toInt()),
// + the fieldKeyMap + toJson entries
```

## The CI gap (the root cause)

`.github/workflows/flutter-ci.yml` → job **`build_runner (verify generated files
up-to-date)`** runs:
```yaml
defaults: { run: { working-directory: mobile } }
- run: dart run build_runner build
- run: git diff --exit-code   # fail if generated files changed
```
`build_runner` only processes the package it runs in. With
`working-directory: mobile`, it regenerates the **app** (`mobile/`) package's
`.g.dart` — but **never** the path-dependency package
`mobile/packages/mopro_api/`. So the package's generated output has **never been
validated by CI** and was free to drift. `make api-gen-dart` runs the
openapi-generator (Docker, `dart-dio`) which emits the `.dart` *source* — the
`.g.dart` still comes from `build_runner`, which nothing in CI ran for the package.

## Stale files found (regen `git diff`)

Exactly **2** — running `build_runner` in `mobile/packages/mopro_api/`:

| File | Change | Kind |
|---|---|---|
| `product_summary.g.dart` | +`isBestseller` / +`basketDiscountPct` (fromJson + fieldKeyMap + toJson) | **real content** — the live bug |
| `delivery_eta.g.dart` | line-wrapping only (Dart "tall-style" formatter) | format drift |

(No other generated files drifted.)

## The fix

1. **Regen** — commit both corrected files from `build_runner` in the package.
2. **Gate** — extend the codegen job to also run `build_runner` **in
   `mobile/packages/mopro_api/`** + `git diff --exit-code`, so the package's
   generated output can't drift again. (The app step is kept; this adds the
   package coverage the gate was missing.)
3. **Regression test** — a `ProductSummary.fromJson` test asserting the merch
   fields parse from a representative payload (belt-and-suspenders; would have
   caught this).

## Version note

Local Dart 3.12 stable produces the committed (tall-style) output; CI's
`flutter-version: '3.x'` stable is the same generation (the app's `.g.dart` gate
already passes green on `main` with tall-style output), so the package regen
matches what the new gate will produce on CI.
