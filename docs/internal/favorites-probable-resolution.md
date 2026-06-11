# Favorites PROBABLE resolution — source-side pass (not a visual walk)

> **Superseded for FAV-05/FAV-06:** both shipped on `feat/favorites-ux` — see
> `docs/internal/favorites-ux.md` (client-side variant resolution, no codegen;
> shared-card §3 trap dodged with a favorites-local wrapper).

Home method: Mopro from code (fact) × Trendyol convention (provisional, ~May 2025,
*not visually verified*). No fabricated observations.

### FAV-05 — no add-to-cart on the favorites card → CONFIRMED gap, DEFER (needs variant resolution)
- **Mopro (fact):** `favorites_screen.dart:93` renders the shared `ProductCard`
  (heart-remove + tap→PDP; already shows bestseller/official/basket-discount). No
  "Sepete Ekle".
- **Trendyol (provisional):** favorites cards have a direct add-to-cart *(convention)*.
- **Verdict:** real gap, but **not a clean UI fix**: favorites store only **product
  IDs** (`Set<int>`), while add-to-cart needs a **variant_id** — a multi-variant
  product can't be added without a picker. So a faithful ATC needs a **quick-add
  sheet or PDP redirect for variant selection**, and adding the button to the shared
  `ProductCard` serializes per §3. **DEFER** (small feature, not a guess-fix). Flag.

### FAV-06 — no sort/filter of favorites → NEEDS-DECISION / DEFER (UI feature)
- **Mopro (fact):** favorites render in insertion order (`Set`); no sort/filter
  control.
- **Trendyol (provisional):** sort (price/discount) + filter *(convention)*.
- **Verdict:** a **UI feature** (sort control + comparator over the loaded products),
  not a clean one-liner; LOW priority. **NEEDS-DECISION** (is it wanted for the lean
  favorites surface?) → DEFER if yes. Flag.

### FAV-07 — no "fiyatı düştü since favorited" indicator → DEFER (needs price-at-favorite snapshot)
- **Mopro (fact):** favorites store **only IDs** — no price-at-favorite snapshot. The
  only price signal is the card's generic lowest-30d strikethrough.
- **Trendyol (provisional):** "price dropped since you saved it" cue *(convention)*.
- **Verdict:** needs a **price-at-favorite snapshot** (favorites schema/data change +
  per-item compare) → **DEFER (backend/data)**. Not a UI-only fix.

## Outcome

| Row | Verdict |
|---|---|
| FAV-05 add-to-cart on card | CONFIRMED → **DEFER** (variant resolution; quick-add sheet / PDP; touches shared card) |
| FAV-06 sort/filter | **NEEDS-DECISION** (UI feature, LOW) |
| FAV-07 price-drop-since-favorited | **DEFER** (price-at-favorite snapshot — data) |

**Zero CONFIRMED UI-only fixes.** FAV-01 (collections) is a known MED gap (separate);
FAV-02 (two-way sync) already RESOLVED. **Discovery shift:** FAV-05 looks like a
simple button but is gated on variant resolution (favorites hold only product IDs).

**NOT-ACTIONABLE (settled, not re-opened):** guest-local favorites (deliberate — no
auth wall), coin/cashback chip.

## Salih's residue (Favorites)
- **NEEDS-DECISION:** FAV-05 (ATC affordance: quick-add sheet vs PDP redirect, and
  is it wanted), FAV-06 (sort/filter on the favorites surface).
- **DEFER (engineering):** FAV-05 (variant-resolution UX), FAV-07 (price-at-favorite
  snapshot), FAV-01 (collections).
