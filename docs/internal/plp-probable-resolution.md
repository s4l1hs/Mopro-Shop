# PLP PROBABLE resolution — source-side pass (not a visual walk)

Home method: Mopro from code (fact) × Trendyol convention (provisional, ~May 2025,
*not visually verified*). No fabricated observations.

### PLP-06 — no predefined quick-filter pills above the grid → NEEDS-DECISION (curated feature)
- **Mopro (fact):** filtering is the sort/filter bar + sheets (mobile) / sidebar
  (desktop); no row of one-tap quick-filter pills ("Kargo Bedava", "İndirimli", …)
  above the grid.
- **Trendyol (provisional):** quick-filter chips above the grid *(convention)*.
- **Verdict:** the pills are a **curated set** wired to existing filters — *which*
  pills + whether they earn the space is a **product decision**, not a source gap.
  **NEEDS-DECISION** (then a small feature). Not guessed.

### PLP-07 — brand facet has no counts → NEEDS-VISUAL (Trendyol-side inconclusive)
- **Mopro (fact):** the brand facet lists brands derived from the loaded page,
  **without counts**.
- **Trendyol (provisional):** *inconclusive* — markup shows facet counts are **not
  in the SSR payload**; whether the live UI shows them can't be settled from source
  or static markup.
- **Verdict:** since the convention is **inconclusive**, this can't be CONFIRMED →
  **NEEDS-VISUAL** (Salih's eyes on the live facet). Softened; not guessed.

### PLP-08 — no-results state had no clear-filters CTA → CONFIRMED → ✅ FIXED
- **Mopro (was):** `CatalogShell` rendered a bare `EmptyState.empty()` for an empty
  grid — even when active filters caused the emptiness; no escape hatch.
- **Trendyol (provisional):** a no-results state offers "clear filters" *(convention,
  + a standard UX expectation independent of Trendyol)*.
- **Verdict:** **CONFIRMED, source-determinable.** **Fixed** — `EmptyState.filtered`
  + `CatalogShell.onClearFilters` (shown only when `activeFilterCount > 0`) +
  `PlpFiltersNotifier.clear()`, wired from the PLP screen. i18n + widget test.

### PLP-10 — no search bar in the PLP header → NEEDS-DECISION (IA)
- **Mopro (fact):** PLP header = category title + share; **no inline search bar**.
  Search is its **own surface** (bottom-nav tab / search screen).
- **Trendyol (provisional):** PLP header carries a search bar *(convention)*.
- **Verdict:** Mopro's IA puts search on a dedicated surface; adding an inline PLP
  search bar is an **IA decision** (duplicate entry point vs. lean header), not a
  source gap. **NEEDS-DECISION (Salih).**

## Outcome

| Row | Verdict |
|---|---|
| PLP-06 quick-filter pills | **NEEDS-DECISION** (curated feature) |
| PLP-07 brand-facet counts | **NEEDS-VISUAL** (Trendyol-side inconclusive) |
| PLP-08 no-results clear-filters CTA | **CONFIRMED → ✅ FIXED** |
| PLP-10 search bar in PLP header | **NEEDS-DECISION** (IA — search is its own surface) |
| §9 unnumbered visual bucket | **NEEDS-VISUAL** (spacing/rhythm — Salih's eyes) |

**1 CONFIRMED fix (PLP-08).** The rest are decisions (PLP-06/10), Trendyol-side
inconclusive (PLP-07), or pure visual (§9). The big PLP gaps (PLP-01/03/04/05/13–20)
were already resolved in prior sprints.

## Salih's residue (PLP)
- **NEEDS-VISUAL:** PLP-07 (facet counts on live Trendyol), §9 spacing/rhythm.
- **NEEDS-DECISION:** PLP-06 (quick-filter pills — which set), PLP-10 (inline PLP
  search bar vs. dedicated search surface).
