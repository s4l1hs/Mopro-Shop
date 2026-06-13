# Size-Fit Recommendation — design (Phase C, design-first)

Users enter body measurements → the PDP recommends the size ("your size: M") with
a fit signal, across all apparel. Standard charts only (no seller tooling yet);
charts are the **EN 13402-3 standard reference** (a baseline, NOT per-brand —
still flagged `chart_approximate`). See *Curation* below.

## Discovery shifts (vs the prompt's assumptions)

1. **Charts key on GARMENT TYPE, not category.** The taxonomy is coarse
   (`112 Kadın Giyim`, `113 Erkek Giyim`, `125 Spor Giyim`, flat `21 Giyim`) — a
   category contains tops AND bottoms, so "category → chart" can't work. Standard
   size charts are inherently per garment type (top/bottom/dress/skirt/
   outerwear). The chart model therefore defines garment types, and the product's
   type is **classified server-side** (below). This supersedes §1.3's
   "category → garment type → size" chain.
2. **Garment classification = attribute-first, TR-keyword fallback.** The PLP-13
   attribute model (`product_attributes`, 0089) can carry an authoritative
   `garment_type` per product (curation path, same flag as charts), but only
   `renk` is seeded today → phase 1 classifies from the product **title** via a
   deterministic TR keyword table (tişört/gömlek/sweat/kazak→top;
   pantolon/şort/tayt/jean→bottom; elbise→dress; etek→skirt; mont/ceket/
   yelek→outerwear). Non-apparel titles match nothing → graceful `no_chart`.
   Flagged approximate alongside the charts.
3. **sizefinder lives in jobs-svc (constitution module map) → this feature
   builds the FIRST core→jobs §3.4 synchronous HTTP path.** No precedent exists
   (jobs-svc serves only `/healthz`; core never calls it). The consumer API
   stays on core-svc (auth, spec, codegen); core calls jobs-svc over the
   internal network. Internal hop guarded by the existing `ADMIN_INTERNAL_TOKEN`
   env (already provisioned on prod; jobs-svc endpoints sit OUTSIDE Caddy's
   public `/jobs/*`-routed paths AND check the token — defense in depth).

## Data model (migration 0096)

- **`ref_schema.size_charts`** (readable by every module — the §5 shared-read
  exception; seeded reference data):
  `garment_type TEXT · gender TEXT (female|male) · size_system TEXT (alpha|eu) ·
   size_label TEXT · sort_rank INT · measurement TEXT (chest|waist|hip) ·
   min_mm INT · max_mm INT · source TEXT`
  PK (garment_type, gender, size_system, size_label, measurement). Originally
  seeded approximate (0096); **curated to the EN 13402-3 standard reference in
  0098** — see *Curation* below. Integer millimetres (no floats — the money-type
  discipline applied to lengths).
- **`sizefinder_schema.fit_profiles`** (owned by `internal/sizefinder`,
  jobs-svc, postgres-ecom; schema already reserved in the boundary map):
  `user_id BIGINT PK (soft ref) · chest_enc/waist_enc/hip_enc/inseam_enc/
   height_enc TEXT (AES-GCM via pkg/crypto.EncryptPII — the 0093 order-address
   pattern) · fit_pref TEXT (regular|loose|tight) · created_at/updated_at`.
  Measurements NEVER stored plaintext (§6); jobs-svc gains `PII_KEK_BASE64`
  in compose (core already has it).

## Match algorithm

Relevant measurements per garment type: top→chest; bottom→waist,hip,inseam;
dress→chest,waist,hip; skirt→waist,hip; outerwear→chest.

For each size (sort_rank order), over the relevant measurements present in the
profile: distance = 0 if value ∈ [min,max], else distance to the nearest bound
(mm). Size score = Σ distances. Recommend the min-score size.
- **Signals:** `true_to_size` (score 0); `between` when the two best adjacent
  sizes are both ≤25 mm total (report both, recommend per `fit_pref`: loose →
  larger, tight/regular → smaller); `size_up`/`size_down` hint when the winning
  size's binding measurement sits in the top/bottom 15% of its range.
- **Fallbacks:** no relevant measurement in the profile → `incomplete_profile`
  (+ which measurements would help); unclassifiable product → `no_chart`;
  every response carries `chart_approximate: true`.

## API (core-svc, spec + codegen; all requireAuth)

- `GET /me/fit-profile` → FitProfile (404-shape `{exists:false}`? → 200 with
  nullable fields; simpler client) · `PUT /me/fit-profile` (upsert, idempotent).
- `GET /products/{id}/size-recommendation` → `{status: ok|incomplete_profile|
  no_chart|no_profile, size?, between?, signal?, missing?, chart_approximate}`.
  Core resolves the product title via `catalog.Service.GetByID` (in-process,
  §3.1), then POSTs `{user_id, title}` to jobs-svc internal
  `/internal/sizefit/recommend` (token header). Profile CRUD likewise proxies
  `/internal/sizefit/profile`. `JOBS_SVC_URL` env (default
  `http://jobs-svc:8080`).

## Mobile

- **Account → "Beden profilim"**: form (chest/waist/hip/inseam/height in cm —
  UI converts to mm; fit preference radio), PUT on save; entry tile in Account.
- **PDP**: under the variant selector, a "Bedenini bul" CTA → if profile
  complete, shows `Önerilen beden: M` (+ signal copy + "yaklaşık" flag); if not,
  routes to the Account form. Goldens on-branch.

## Build plan (commit per concern)
1. Design doc (this).
2. Migration 0096 (`ref_schema.size_charts` seed + `sizefinder_schema.fit_profiles`) + init lockstep.
3. `internal/sizefinder`: domain/repo/service (EncryptPII profile CRUD; classifier; match) + unit tests.
4. jobs-svc internal HTTP endpoints (token-guarded) + core-svc consumer handlers (catalog resolve + proxy) + spec/codegen + contract tests.
5. Mobile: Account fit form + PDP CTA + i18n + tests.
6. Audit/feature doc + ledger.

## Curation — EN 13402-3 standard reference (migration 0098)

Replaces the phase-1 representative seed with the **EN 13402-3** standard —
the European clothing-size standard (body dimensions in cm; the correct baseline
for a TR/EU-sizing market). What changed:

- **Garment → dimension map = EN 13402-2.** No drift: the match's
  `relevantMeasurements` already matched EN (tops→bust/chest; women's
  bottoms→waist+hip; men's bottoms→waist; dresses→bust+waist+hip; skirts→
  waist+hip). EN's gender asymmetry on bottoms is honoured at the *chart* level —
  men's bottom charts carry waist only (no hip rows), so a man's hip simply isn't
  scored (degrades to waist).
- **Gender axis added** (`gender` column): EN women's **bust** bands ≠ men's
  **chest** bands, and women's bottoms add hip. `genderForChart` resolves women-
  only garments (dress/skirt) to female, otherwise male-iff-male-else-female
  (the default for unspecified). The repo queries `gender` + `size_system`.
- **Two size systems** (`size_system` column): **alpha** (S–XXL) is what the
  match returns; **EU numeric** (32–58) is seeded as a parallel reference set
  (women dress + men top) proving the numeric axis is representable. The match
  consumes alpha only (repo filters `size_system='alpha'`); EU is reference data
  for future numeric-label products.
- **Provenance** (`source` column): every curated row is
  `EN 13402-3 (standard reference)`. The basic-mode bands are tagged separately
  in code as `retail height/weight bands (approximate)` (see size-fit-basic.md).
- **Inseam/height** (EN 13402-3 §3c/§4) are secondary, height-driven length
  bands — documented here but **not** seeded as size_charts rows (the match has
  no length axis; inseam is collected on the profile but unused in phase 1).

**Honesty unchanged.** This is a **standard baseline, NOT per-brand truth** —
real garments vary by brand/cut/fabric. The API still flags every response
`chart_approximate: true`; the basic-mode warning is untouched. **Seller-entered
charts that override this baseline per product are the next item** — the `source`
column is the seam they plug into.

> **Provenance / licence.** EN 13402-1/-2/-3 via the OnlineConversion EN 13402
> reproduction (GFDL, derived from Wikipedia's EN 13402 article); supplementary
> height/weight→size bands from published retail fit charts. The EN values are an
> industry standard, not proprietary brand data; the reproduction is GFDL.

## Out of scope / follow-ups (flagged)
- **Seller-entered charts** that override the standard baseline per product
  (the attribute write-path) — *next item*; plugs into the `source` seam.
- Fuller EU-numeric seeding (all garments/sizes) — schema already supports it
  via `size_system='eu'`; only a representative sample is seeded today.
- Attribute-driven `garment_type` (curation via PLP-13 write-path) replacing the
  keyword classifier; card-level fit chips.
