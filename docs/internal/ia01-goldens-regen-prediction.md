# IA-01 goldens regen — prediction (predict-then-verify)

> Committed BEFORE dispatching `golden-rebaseline.yml` on `chore/ia01-goldens-regen`.
> IA-01 (`feat/home-ia-restructure`, merged) made two mobile-visible changes whose golden
> baselines were never regenerated (macOS can't enumerate Linux flips — the platform guard
> fails all Linux baselines locally). This regen lands the Linux baselines.

## Predicted flips — EXACTLY 5 `.png` (+ their `.png.meta` sidecars)

IA-01 change → golden:

1. **Home category section: grid → `HomeCategoryRail`** (horizontal shortcut rail + "Tüm
   Kategoriler" puck). Flips the 3 responsive Home goldens:
   - `mobile/test/features/home/goldens/home_mobile_375.png`
   - `mobile/test/features/home/goldens/home_tablet_768.png`
   - `mobile/test/features/home/goldens/home_desktop_1440.png`

2. **Bottom-nav: Categories tab → Coin tab** (`Icons.monetization_on`, label `nav.coin`).
   Flips the 2 bottom-nav goldens:
   - `mobile/test/shell/goldens/bottom_nav_light.png`
   - `mobile/test/shell/goldens/bottom_nav_dark.png`

## Predicted NON-flips (must stay byte-identical)

- `recs_home_*`, `recs_pdp_*`, `flash_deals_*` (home dir) — different widgets, IA-01 untouched.
- `web_header_*`, `account_hover_menu_*`, `search_suggestions_*` (shell dir) — web header /
  hover menus / search, not the mobile bottom nav.

## Verify

After the workflow auto-commits, `git diff --stat main...chore/ia01-goldens-regen` must show
**exactly the 5 `.png` above (+ matching `.png.meta`) and nothing else**. Any extra flip is
investigated before merge (predict-then-verify discipline).
