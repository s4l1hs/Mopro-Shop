# P-029 Frontend Un-Hide — discovery

> Follow-up to PR #90 (`feat/bestseller-sort`), which made the backend honor
> `sort=bestseller` end-to-end via in-process global popularity. PR #86 had
> hidden the option in the PlpSort UI pending that backend. This PR removes the
> now-stale hide. **Mobile-only; no backend, no spec, no schema.**

## 1. The hide mechanism — exactly two sites

PR #86 (`898eeef4 feat(p026): hide bestseller, disable cashback_only, wire in_stock UI`)
hid the option in **two** selectors via a `.where(... != bestseller)` filter:

| # | File:line | Surface | Filter |
|---|---|---|---|
| 1 | `sort_sheet.dart:59` | **Mobile** bottom sheet (`SortSheet`) | `..._sortOptions.where((o) => o.$1 != 'bestseller')` |
| 2 | `category_products_screen.dart:235` | **Desktop** `PopupMenuButton<PlpSort>` (`_sortDropdown`) | `PlpSort.values.where((s) => s != PlpSort.bestseller)` |

These two cover **every** selection entry point (verified):
- All mobile sort buttons route through `showSortSheet` → `SortSheet`:
  `category_products_screen.dart:256` (category PLP) and `search_screen.dart:162` (search). Fixing #1 covers both.
- The only widget that *enumerates* `PlpSort.values` for selection is `_sortDropdown` (#2).
  The only other `PlpSort.values` use is `PlpSort.fromToken` (resolution loop — already includes bestseller).
- `catalog_shell.dart:146` (`_sortLabel`) is a *display* resolver, not a hide — it already maps
  `'bestseller' => 'catalog.sort_bestseller'.tr()` for the active-sort chip.

**Fix:** drop both `.where(...)` filters (and the stale comments). ≤30 LOC.

## 2. i18n — keys already correct (no change)

The prompt assumed TR=`"En Çok Satan"` / EN=`"Bestseller"` and "verify; add if placeholder."
Discovery falsifies the assumption but finds the keys **present, valid, and consistent**:

| key | tr-TR.json | en-US.json |
|---|---|---|
| `catalog.sort_bestseller` | `"Çok satanlar"` | `"Best sellers"` |
| `home.rail_bestseller` (home bestseller rail) | `"Çok satanlar"` | `"Best sellers"` |

- Not a placeholder; idiomatic Turkish; fits the sort family (`Önerilen`, `En yeniler`, …).
- **Identical to the home bestseller rail label** → changing the sort label alone would *desync* the
  two surfaces; changing both is a deliberate wording decision touching `home_provider` (out of scope §1.2).
- Trendyol's exact label is `"En çok satanlar"` (with `En`); the app's established choice is `"Çok satanlar"`.
  Aligning is a trivial, *separate* wording PR (both keys) if the product owner wants it — not required here.
- The key is **not dead even while hidden**: `catalog_shell.dart:146` references it via a static `.tr()`.

**Decision: keep the values.** Per §3.2 "if the value is already correct, skip this commit." i18n
declared-count unchanged; 0 dead / 0 missing.

## 3. URL codec — already round-trips bestseller

`plp_filters_codec.dart`: `encode` writes `f.sort.token` (`'bestseller'`); `decode` uses
`PlpSort.fromToken(q['sort'])`. `PlpSort.bestseller` has `token == 'bestseller'` and `fromToken`
resolves it. So `?sort=bestseller` already round-trips (it did under #86 too). Guarded by a new unit case.

## 4. No dependency on PR #90's client regen

The generated client takes a **raw string** sort param —
`catalog_api.dart:413 String? sort` and `search_api.dart:60 String? sort` — and the providers call
`api.listProducts(sort: f.sort.token)` / `api.search(sort: f.sort.token)` (a `String`). So sending
`sort=bestseller` works regardless of whether the generated `FilterSort` enum lists it. This PR is
**functionally independent** of #90; it is *stacked* on #90 only to avoid docs-file merge conflicts
(both edit AUDIT/ROADMAP/REPORT). GitHub auto-retargets the base to `main` when #90 merges.

## 5. Goldens — zero flips (evidence-backed)

The prompt predicted "2 sort-selector goldens regenerate." **Falsified for this codebase:**
- Desktop `_sortDropdown` is a `PopupMenuButton`; its items render only in the *tapped overlay*.
  `plp_goldens_test.dart` captures the **closed** sidebar (`plp_sidebar_*`) and never taps the dropdown,
  so the hidden option was never in any golden. The closed button shows the *current* sort label
  (default `recommended`), which un-hiding does not change.
- The mobile `SortSheet` has **no golden** (no existing test references it).

→ **No golden regen.** Commit-5 (goldens) is a documented no-op.

## 6. Test plan (commit 3)

| Test | File | Asserts |
|---|---|---|
| codec round-trip + token | `plp_filters_test.dart` (extend) | `encode/decode` of `sort: bestseller`; `fromToken('bestseller')`; `decode({'sort':'bestseller'})` |
| mobile sheet renders option | `sort_sheet_test.dart` (**new**) | `SortSheet` shows a `RadioListTile` value `'bestseller'` (key `catalog.sort_bestseller`); 6 options total |
| desktop popup renders option | `category_products_desktop_test.dart` (extend) | opening `PopupMenuButton<PlpSort>` shows `catalog.sort_bestseller` |

`.tr()` returns the **key** in tests (no bundle loaded) — assert on `catalog.sort_bestseller` / the
`RadioListTile.value`, never the Turkish string.

## 7. Commit plan

1. this doc.
2. un-hide (both `.where` filters + stale comments).
3. tests (codec + mobile sheet + desktop popup).
4. docs closure — AUDIT P-029 end-to-end RESOLVED; ROADMAP; REPORT.

i18n (skip, §2) and goldens (skip, §5) are documented no-ops, not commits.

## 8. Out of scope / follow-ups

- Backend (#90 shipped it); P-031 (category-scoped popularity); P-007; P-030; chi-square flake.
- `"Çok satanlar"` → `"En çok satanlar"` Trendyol-exact wording (both sort + rail keys) — optional product call.
