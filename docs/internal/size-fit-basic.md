# Size-Fit Basic Estimation Mode — design (builds on #214)

Two-tier fit estimation so users who don't know detailed measurements still get
a size from **height + weight + gender**, honestly flagged approximate; and
partial profiles degrade gracefully instead of erroring.

## The three tiers (confidence on every recommendation)
- **DETAILED** — every garment-relevant measurement is a REAL profile value →
  high-confidence size, no warning.
- **BASIC** — at least one relevant measurement was **estimated** from
  height/weight/gender (full basic profile, or a partial detailed profile with
  gaps filled) → same size machinery, shown with a clear "approximate" warning.
- **NONE** — neither the relevant measurements nor enough basic inputs
  (height+weight+gender) to estimate → prompt to complete the profile. **Never a
  fabricated size.**

## Estimation method — chosen: (a) estimate-then-match

Estimate each MISSING relevant measurement from height/weight/gender via simple
gender-specific linear approximations, then run the **existing** `scoreSizes` /
`applySignal` chart match on the real+estimated measurements.

**Why (a) over (b) a direct height/weight→size table:**
- **One source of truth** — the size ladder stays the `ref_schema.size_charts`
  ranges; basic mode only synthesizes inputs, so DETAILED and BASIC always agree
  on what "M" means (a separate table could drift from the charts).
- **Partial profiles fall out for free** — estimate only the gaps (e.g. user has
  waist but not hip → estimate hip, match on both) → BASIC. No special-casing.
- **One thing to curate** — the charts. (b) would add a second per-garment seed
  to curate in lockstep.
- Reuses the shipped match end-to-end (between-sizes, edge hints, statuses).

**Estimation formulas (illustrative — APPROXIMATE, curate alongside the charts).**
Circumference in mm scales mainly with weight, with a small height term and a
gender base. Fit-only; no BMI, no health/judgment framing.
```
kg = weight_g/1000 ; dh = (height_mm/10) - 170   // cm above/below 170
female: chest = 6600 +? ...   (see basic_estimate.go constants)
```
Coefficients chosen so average inputs land mid-chart (e.g. male 80 kg/180 cm →
~L, female 60 kg/165 cm → ~S/M). They are deliberately rough — the BASIC warning
says so, and curation replaces them with proper anthropometric tables.
inseam is not chart-used in phase 1, so basic mode estimates only chest/waist/hip.

## Confidence rule
DETAILED iff every relevant measurement for the garment was a real profile
value; BASIC iff ≥1 was estimated; the `estimated[]` list names which.
The existing fit signals (true_to_size/between/size_up/down) ride along
unchanged — confidence is orthogonal to signal.

## Data model (migration 0097 — additive)
`sizefinder_schema.fit_profiles` gains:
- `weight_enc TEXT` — weight in **grams** (integer), AES-GCM `EncryptPII` at rest
  (§6 — same as the measurements; weight is sensitive body data).
- `gender TEXT` — `female | male | unspecified` (default unspecified). Categorical
  preference, not a measurement → stored plaintext like `fit_pref`. `unspecified`
  → basic estimation unavailable for that user (treated as missing input).
Init lockstep: `85-sizefinder-schema.sql`.

## API additions (spec + codegen)
- `FitProfile`: + `weight_g` (int), `gender` (string).
- `SizeRecommendation`: + `confidence` (`detailed | basic`), `estimated[]`
  (measurements that were estimated). `status` semantics unchanged except
  `incomplete_profile`/`no_profile` now only fire when basic estimation also
  can't run.

## UX
- **PDP** card: BASIC (or any rec with `estimated` non-empty) renders an
  "≈ yaklaşık — kesin olmayabilir" warning line under the size; DETAILED renders
  clean; NONE keeps the existing complete-profile CTA.
- **Fit form**: add weight (kg) + gender; copy makes clear detailed = best,
  basic (height+weight+gender) = approximate. Neutral, fit-only wording.

## §5 / §6
§6: height + weight encrypted (EncryptPII), gender plaintext-categorical, all in
sizefinder_schema. §5: unchanged — core resolves the title in-process and proxies
to jobs-svc; no cross-schema JOIN.

## Build plan (commit per concern)
1. Design doc (this).
2. Migration 0097 (weight_enc + gender) + init lockstep + repo encrypt/decrypt.
3. Basic-estimate logic + confidence in `Recommend` (estimate-then-match) + unit tests (detailed/basic/partial/none).
4. Spec + codegen (confidence/estimated/weight_g/gender) + contract test.
5. Mobile: PDP warning + fit-form basic fields + i18n (TR+EN) + tests.
6. Doc + ledger.

## Shipped
Migration 0097 (weight_enc + gender), basic-estimate tier + confidence in the
match service (estimate-then-match), spec/codegen (confidence/estimated/weight_g/
gender), PDP approximate warning (BASIC only), fit-form basic fields. Tests cover
detailed/basic/partial/none. Estimation coefficients remain **illustrative** —
curate alongside the charts.
