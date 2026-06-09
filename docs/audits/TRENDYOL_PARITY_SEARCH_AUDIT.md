# Trendyol Parity Audit — Search

> **Audit only — no code.** Self-audit of the Search surface (bar + entry points,
> suggestions/autocomplete, query results page, no-results) against a
> **provisional** Trendyol baseline. `/sr` is bot-blocked (403) → **no markup for
> Trendyol search**; this leans on the impl self-audit (`src`) + Salih's live
> walk. Sibling of `TRENDYOL_PARITY_PLP_AUDIT.md`; findings use the #09 format,
> IDs **SE-NN**.
>
> **Surface (source):** `SearchScreen` (`lib/features/catalog/screens/
> search_screen.dart`) · `searchProvider` · `recent_searches_provider` ·
> `SearchInput` · `web_search_pill` + `SearchSuggestionsDropdown` (desktop header)
> · `header_search_bar` · backend `SearchProductsSummary`. The results page reuses
> the PLP substrate (`CatalogShell` · `FilterPanel` · `PlpFilterChips` · `sort` ·
> `plpFiltersProvider(plpKeyForSearch(q))`).

---

## §0 — Legend

- **Source** — `src` (Mopro code fact) · `walk` (Salih, search-specific/visual).
  *No `markup` row — Trendyol `/sr` is 403.*
- **Confidence** — **CONFIRMED** (structural source fact) · **PROBABLE**
  (search-specific / visual — awaits the walk) · **NOT-ACTIONABLE** (intentional).

---

## §1 — Summary

- **PLP-inheritance: PARTIAL** (the headline — see §2). Shared *widgets* carry
  over; the **screen-level** PLP improvements do **not**, because `SearchScreen`
  reimplements the results wiring separately from `CategoryProductsScreen`.
- **CONFIRMED search-specific deltas (src): 7** — SE-02 (mobile search has **no
  filter** affordance), SE-03 (no result count), SE-04 (load-more, no infinite-
  scroll/numbered-pages), SE-05 (flat breakpoints), SE-06 (no brand/product
  autocomplete), SE-07 (no "did you mean"/no-results recovery), SE-09 (mobile
  empty lacks trending).
- **PROBABLE (await walk): 2** — SE-08 (relevance ranking), SE-10 (search-within /
  sponsored).
- **NOT-ACTIONABLE: 4** — no camera (HP-04 dropped), no sponsored ads (no ads
  model), cashback chip on cards, brand-orange tokens.
- **Already-matched: ~8** (§5). **Seed:** local search **exercisable** (§6).

---

## §2 — PLP-inheritance check (the key §1.1 deliverable)

`SearchScreen` reuses the PLP **components** but has its **own** `_results`/`_shell`
wiring → it did **not** pick up the recent per-screen PLP fixes:

| PLP item | Inherited by search? | Why |
|---|---|---|
| Grid (`ProductGrid` via `CatalogShell`) | ✅ yes | shared shell |
| Desktop filter sidebar (`FilterPanel`, no category tree) | ✅ yes | mounted in `_results` |
| Applied chips (`PlpFilterChips`, desktop) | ✅ yes | mounted in `_results` |
| Sort (`PlpSort` + sort sheet/dropdown) | ✅ yes | wired |
| **PLP-20** sticky sort/filter bar | ✅ yes | lives in the shared `CatalogShell` |
| **PLP-18** sticky desktop sidebar | ✅ yes | same height-bounded column layout |
| Empty / error states | ✅ yes | shared shell |
| **PLP-04** result count | ❌ **no** | `SearchState` has no `total`; `_shell` passes no count → **SE-03** |
| **PLP-03 / PLP-15** infinite scroll / numbered pages | ❌ **no** | `_shell` uses `onLoadMore` (load-more) on **all** breakpoints → **SE-04** |
| **PLP-19** ultra-wide breakpoints (2/3/4/5) | ❌ **no** | search uses flat `wide ? (5/3) : 2` → **SE-05** |
| Mobile filter sheet (PLP-01) | ❌ **no** | `_shell` sets `onSort` but **not** `onFilter` on mobile → **SE-02** (mobile search can't filter at all) |
| **PLP-12** subtree rollup | n/a | search isn't single-category scoped |

> **Discovery shift:** "inherited from PLP" is only true for the *shared widgets*.
> The screen-level wins (count, pagination model, breakpoints, mobile filtering)
> need to be **ported** to `SearchScreen` — they're the same fixes, not new work.
> Cleanest long-term: factor the PLP/search results body into one shared screen.

---

## §3 — Search-specific findings (registry)

| ID | Finding (Mopro current → Trendyol) | Source | Confidence | Sev |
|---|---|---|---|---|
| **SE-01** | PLP-inheritance is **partial** (shared widgets only; screen-level wiring not ported) — see §2 | src | **CONFIRMED** | — |
| **SE-02** | ~~mobile search has no filter~~ → **RESOLVED** (Session 1): `_shell` wires `onFilter` → `showPlpFilterSheet(plpKey, brands)` on mobile. | src | **RESOLVED** | **MED** |
| **SE-03** | No **result count** ("X ürün"). **UI wired (Session 1)** — `SearchState.total` (nullable) → `_ResultCount` on both; lights up with the backend `pagination.total` (see Session 2's note). | src | **RESOLVED** (UI) | MED |
| **SE-04** | ~~load-more on both~~ → **RESOLVED** (Session 1): `SearchState.totalPages` + `goToPage`; `CatalogShell` mounted with `infiniteScroll` (mobile) + numbered pages (desktop). | src | **RESOLVED** | MED |
| **SE-05** | ~~flat breakpoints~~ → **RESOLVED** (Session 1): `_gridColumns` 2/3/4/5 (mirrors PLP-19). | src | **RESOLVED** | LOW |
| **SE-06** | Suggestions dropdown = recent + trending + **category** shortcuts; **no brand**, **no product (as-you-type)** suggestions | src | **CONFIRMED** (Trendyol-side PROBABLE) | MED |
| **SE-07** | No-results = generic `EmptyState.empty()`; **no "did you mean"/spelling correction**, no suggested alternatives | src | **CONFIRMED** (Trendyol-side PROBABLE) | MED |
| **SE-08** | Results order by the `PlpSort` token (default `recommended`), **not ts_rank relevance** → no relevance ranking | src | **PROBABLE** (backend; confirm) | MED |
| **SE-09** | Mobile empty-search shows recent + categories but **not trending** (the desktop dropdown has trending) | src | **CONFIRMED** | LOW |
| **SE-10** | No "search within results" refine box; no sponsored results | src | **PROBABLE** | LOW |

> Search-bar mic, exact suggestion styling, relevance quality, and no-results copy
> are **visual/behavioural** → confirm in the walk (§7).

---

## §4 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — No camera / visual-search** in the search bar (HP-04 deliberately dropped).
- **D2 — No sponsored / ad results** (Mopro has no ads model).
- **D3 — Cashback chip** on result cards (Mopro perpetual-cashback model).
- **D4 — Brand-orange tokens** on active suggestions/filters.

---

## §5 — Already-matched (VERIFIED from source)

Search bar + entry points (desktop header `WebSearchPill`, mobile home pill →
`/search`) · **recent-search persistence** (`recentSearchesProvider`: chips,
removable, clear-all) · **trending** queries (desktop dropdown) · **category**
suggestions (dropdown + mobile empty) · the **PLP grid + desktop filters + chips +
sort + sticky bar** (inherited shared widgets, §2) · empty/error states · query
echo (mobile AppBar input; desktop a query Chip) · debounced (300 ms) query.

---

## §6 — Seed / index adequacy

Local search is **exercisable**: title/`search_vector`/brand matching over the
seed returns results — `nike` → 6, `ayakkab` → 2, `iphone`/`apple` → 6. The walk
can drive real queries. (Note: results aren't relevance-ranked — SE-08.)

---

## §7 — Walk-findings slots (Salih — search-specific; #09 format)

> The search-specific bits need your eyes: suggestion completeness, no-results
> recovery, relevance quality, mic. Paste observations; flip PROBABLE → CONFIRMED
> + severity (or NOT-ACTIONABLE). New items continue at **SE-11+**.

```
### SE-NN — <one-line title>
- **Surface/region:** Search › <bar | suggestions dropdown | results grid | no-results | empty>
- **Trendyol (live):** <observation>  [walk date: ____]
- **Mopro (current):** <file:line if known>
- **Delta / Status / Severity / Notes>
```

<!-- SE-06 — confirm Trendyol's autocomplete shows brand + product suggestions. -->
<!-- SE-07 — confirm Trendyol's no-results: "did you mean" + popular alternatives. -->
<!-- SE-08 — confirm Trendyol's default is relevance-ranked. -->
<!-- SE-11 … -->

---

## §8 — Prioritized fix list (after the walk)

1. **Port the screen-level PLP wins to `SearchScreen`** (SE-02/03/04/05) — same
   fixes already shipped for the PLP: **mobile filter sheet** (SE-02, the real
   gap), **result count**, **infinite-scroll/numbered-pages**, **2/3/4/5
   breakpoints**. *Cheapest path: extract a shared results body.*
2. **SE-06** — brand + product (as-you-type) suggestions in the dropdown.
3. **SE-07** — no-results recovery ("did you mean" + popular alternatives).
4. **SE-08** — relevance default sort (backend ts_rank) — confirm + backend track.
5. **SE-09 / SE-10** — trending on mobile empty; refine box. LOW.

> Severities provisional until the walk. **PLP findings that auto-apply to
> search:** PLP-20 (sticky bar) ✅ already; PLP-13/14 (attribute / price-history
> facets) would surface in the shared `FilterPanel` → search inherits them when
> built. No fixes in this PR.
