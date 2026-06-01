# Tranche 5 baseline audit (read-only)

Dual-domain tranche: seller-facing + platform growth. Date: 2026-05-31. Base:
`main` @ PR #30 merged.

## 2.2 Seller surface

| Item | State | Evidence |
|---|---|---|
| `sellers` / `seller_profiles` table | **Missing** | no migration. Storefronts are greenfield. |
| `products.seller_id` | Exists (bare) | `catalog_schema.products.seller_id BIGINT NOT NULL` (migration `0010`), indexed; **no FK / no seller entity** — just an id. |
| Seller display name | Denormalized string | `Product.sellerName` (string) on the catalog DTO; no `Seller` object/rating. |
| `is_seller` (Q&A answers) | **Hardcoded false** | `ugc_service.go:124-126` — "no user↔product seller association exists in v1 → always false". Needs the `seller_users` binding. |
| `PdpSellerCard` | Exists | `mobile/lib/features/catalog/widgets/pdp/pdp_seller_card.dart` — takes `sellerName` + optional `onTap` (routes "to the seller's store when provided"; currently no store exists). |
| Seller routes (backend) | One | `GET /seller/orders/{id}/breakdown` (sellerpayout transparency). No storefront/dashboard routes. |
| Role gating | **None** | no `seller_users`, no `RequireSellerRole`. |

## 2.3 Returns surface (for the approval carry)
- `internal/order/returns.go`: `ReturnStatus` enum incl. `ReturnPending`/`ReturnApproved`/`ReturnRejected`; `return_status_history` table; transitions write history. The seller-approval can hook the existing state machine + refund mechanic.

## 2.4 Q&A surface (for the inbox carry)
- `product_questions` + `product_answers` (Tranche 3); answer endpoint exists; `is_seller` is the only missing piece (always false today → needs `seller_users`).

## 2.5 Flutter web SEO substrate — **stock SPA, no per-route head**
- `mobile/web/index.html`: stock Flutter (`<meta name="description" content="A new Flutter project.">`, `<title>mopro</title>`, `flutter_bootstrap.js async`). **No OG/Twitter tags, no templating, no SSR/proxy.** Per-route meta requires **runtime `dart:html` head mutation (Option B)** — modern crawlers (Googlebot) execute JS and pick it up; documented trade-off. No build infra needed (so §1.6 trigger #3 NOT met).

## 2.6 Share API
- **None.** No `share_plus`, no `navigator.share`, no share buttons. Greenfield (add `share_plus` — standard package).

## Scope assessment + §1.6
Both halves are large greenfield, each ≈ a full large PR:
- **5a Seller-facing:** migration `0078` (new `sellers` + `seller_users` + seed), 3 storefront endpoints, 3 return-approval endpoints + `RequireSellerRole` middleware, Q&A-inbox endpoint, ~12 backend tests; storefront screen (3 tabs) + PDP integration; seller dashboard + returns inbox + questions inbox (role-gated); flows GG/HH/II; goldens.
- **5b Platform growth:** `share_plus` + `MoproShareButton` ×4 surfaces; `MetaTagsService` (dart:html) + per-route; `StructuredDataService` (JSON-LD) + per-route; `/sitemap.xml` + `/robots.txt` backend; `/account/browsing-history` see-all + rail entry; flows JJ/KK/LL; goldens.

Per §1.6 trigger #2 (seller storefront greenfield = new schema + module + non-trivial frontend), the split is justified; this is ≥2 sessions. Two decisions surfaced to the user before §3: **(1) which half to ship this turn**, and **(2) the seller architecture (A/B/C)** for the seller half.
