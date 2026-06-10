# PLP-13 PR 4 — FilterPanel attribute facet (renk) — discovery

> Render the `renk` attribute facet as a `FilterPanel` accordion, consuming the
> `GET /categories/{id}/facets` endpoint + the `attr` filter that shipped in #160.
> **No codegen** — endpoint + client exist. Verified on
> `feat/plp-13-filterpanel-facet`.

## What already exists (#160)

- **Endpoint/client:** `CatalogApi.getCategoryFacets(id)` →
  `GetCategoryFacets200Response { List<Facet> facets }`; `Facet { slug, name,
  List<FacetValue> values }`; `FacetValue { value, count }`. `name` is resolved
  server-side from `Accept-Language` → **no new i18n key for the facet title**.
- **Filter param:** `CatalogApi.listProducts(attr: List<String>?)` — repeated
  `<slug>:<value>` (e.g. `attr=renk:Siyah&attr=renk:Beyaz`); values within a slug
  OR, distinct slugs AND.

## The pattern to mirror

- **`PlpBrandFacet`** (`plp/widgets/plp_facets.dart`) — dense checkboxes bound to
  `plpFiltersProvider(plpKey)`; toggles list membership. The new
  `PlpAttributeFacet` mirrors it (one checkbox per `FacetValue`, with its count).
- **`FilterPanel`** mounts facets via `_section(titleKey, body)` and already
  carries `currentCategoryId` — the key the facets endpoint needs. Search mounts
  `FilterPanel` with `currentCategoryId: -1` (no category) → the facet section is
  **category-gated** (hidden when ≤ 0); search inherits the widget, data shows
  once a category scopes it.
- **`PlpFilters`** round-trips via **`PlpFiltersCodec`** (URL query). Adding
  `attrs` means: state field + codec + `==`/hashCode + chip count.
- **`PlpFilterChips`** builds removable chips via a `chip(label, remove)` helper.
- **`filteredProductsProvider._load`** is where filters → `listProducts(...)`; add
  `attr:` built from `attrs`.

## Plan (commits)

1. discovery (this doc).
2. **state + codec** — `PlpFilters.attrs : Map<String,List<String>>` (slug →
   values) + copyWith/isEmpty/chipCount/==/hashCode; `PlpFiltersCodec` encodes
   `attr_<slug>=v1,v2` and decodes it back (defensive).
3. **providers + wiring** — `attributeFacetsProvider(categoryId)` (FutureProvider
   family → `getCategoryFacets`); `PlpFiltersNotifier.toggleAttr(slug, value)`;
   `filteredProductsProvider._load` passes `attr`.
4. **UI** — `PlpAttributeFacet` (mirror `PlpBrandFacet`); a `FilterPanel` section
   per facet (gated on `currentCategoryId > 0`); `PlpFilterChips` attr chips.
5. **test + audit/ledger.**

## Discovery shifts

- **Facet titles are server-localized** (`Facet.name` via `Accept-Language`) → the
  renk label needs **no client i18n** (i18n 0/0).
- **Search inheritance is category-gated**, not absent: the shared `FilterPanel`
  carries the section, but the per-category facets endpoint means it only renders
  with a real `currentCategoryId` (PLP), not on the `-1` search mount.
- Internal `attrs` is a **`Map<slug, values>`**; the wire `attr` param is the
  flattened `<slug>:<value>` list — converted only at the `_load` boundary.
