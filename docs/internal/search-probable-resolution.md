# Search PROBABLE resolution — source-side pass (not a visual walk)

Home method: Mopro from code (fact) × Trendyol convention (provisional, ~May 2025,
*not visually verified*). No fabricated observations.

### SE-08 — search not relevance-ranked → CONFIRMED → ✅ FIXED
- **Mopro (was):** `catalog.SearchProducts` (`repository.go:207`) matched
  `search_vector @@ plainto_tsquery` (+ ILIKE fallback) but `ORDER BY p.id ASC` —
  results in **id order, not relevance**. (The audit's note that #152 added ts_rank
  did not match current `main` — **discovery shift**: SE-08 was genuinely open.)
- **Trendyol (provisional):** default search sort is relevance *(convention, + a
  universal search expectation independent of Trendyol)*.
- **Verdict:** **CONFIRMED, source-determinable.** **Fixed** — `ORDER BY
  ts_rank(search_vector, plainto_tsquery(...)) DESC, p.id ASC` (DISTINCT dropped:
  the `(product_id, locale)` PK makes the locale-JOIN 1:1). Verified on the seeded DB.

### SE-10 — no "search within results" refine box; no sponsored results → NOT-ACTIONABLE (sponsored) + NEEDS-DECISION (search-within)
- **Mopro (fact):** no in-results refine box; **no sponsored/ad results**.
- **Trendyol (provisional):** a "search within" refine box + **sponsored** results
  *(convention)*.
- **Verdict (two parts):**
  - **Sponsored results → NOT-ACTIONABLE.** Mopro has **no ads model** (settled
    divergence, like the no-camera/PSP calls — not re-opened per §5.3).
  - **Search-within refine box → NEEDS-DECISION.** A second-order refine UX on top of
    the existing filters; whether it earns its place is a **product decision**, not a
    source gap. Flagged, not guessed.

## Outcome

| Row | Verdict |
|---|---|
| SE-08 relevance ranking | **CONFIRMED → ✅ FIXED** (ts_rank default sort) |
| SE-10 sponsored results | **NOT-ACTIONABLE** (no ads model — settled) |
| SE-10 search-within refine box | **NEEDS-DECISION** (product) |

**1 CONFIRMED fix (SE-08).** Most Search rows were already matched (SE-01/03/etc.);
the camera/visual-search row was dropped (HP-04 settled). **Discovery shift:** SE-08
was *not* already done — current `main` searched in id order.

## Salih's residue (Search)
- **NEEDS-DECISION:** SE-10 search-within refine box (wanted, or do the existing
  filters suffice?).
- *(Sponsored ads: NOT-ACTIONABLE — no ads model.)*
