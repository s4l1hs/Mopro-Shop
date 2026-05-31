# Tranche 3 baseline — review submission + Q&A (pre-PR)

Read-only §2 confirmation. `Exists — file:line` or `Missing`.

## Reviews surface (PR #18)

| Item | Finding |
|---|---|
| `product_reviews` table | **Exists** — `catalog_schema.product_reviews` (migration `0064_home_features`). Columns: id, product_id, user_id, rating (1–5 CHECK), title, body, helpful_count, created_at, updated_at. |
| `(product_id, user_id)` unique | **Exists already** — `UNIQUE (product_id, user_id)` in 0064. **No backfill needed; §3.1's ADD CONSTRAINT is a no-op.** |
| `title` / `updated_at` columns | **Exist already** (0064). §3.1's ALTER for these = no-op. |
| `status` / `submitted_locale` columns | **Missing** — 0073 adds them. |
| `product_review_revisions` | **Missing** — 0073 adds it. |
| Reviews service | **Exists** — `internal/catalog` (api.go/service.go/repository.go): ListReviews, ReviewsSummary, ReviewProductID, ToggleHelpfulVote + helpful-vote primitives + `RefreshHelpfulCountCache`. **No write-side (POST/PUT/DELETE) yet** — 0073/handlers add it. |
| `GET /products/:id/reviews` | **Exists** (PR #18, sort+paginate). List filter extends to `status='published'`. |
| Order-item review eligibility | **Missing** — `OrderItem`/order_item_dto have no `review` block. §3.2 adds it like Tranche 1's returnable items. |

## Q&A surface

| Item | Finding |
|---|---|
| `product_questions` / `product_answers` | **Missing** — fully greenfield. |
| Q&A endpoints / service | **Missing**. |
| PDP "Sorular" tab | **Placeholder** — `product_detail_screen.dart` has 4 tabs; the 4th (`product.qa_tab`) renders `_StubTab`. **Replacing it with a real PdpQaTab is a one-line TabBarView child swap** (no restructure). |

## Account rail

`AccountLeftRail` order (post-Tranche 1/2): Profil, Siparişlerim, İadelerim, Cüzdanım, Adreslerim, Kartlarım, Güvenlik, Bildirimler · Yardım … "Yorumlarım" + "Sorularım" go after İadelerim (UGC grouping), before Cüzdanım. Sub-route highlight (`accountRailItemFor`) inherits by `startsWith`.

## §1.6 escape-hatch assessment — NOT triggered (ship as one PR)

1. **Reviews entanglement:** the write-side is **purely additive** — the unique
   constraint already exists (no refactor/backfill), the reviews service is in
   `internal/catalog` and gains POST/PUT/DELETE methods without touching the
   read/helpful paths. No state-machine disruption. **Condition not met.**
2. **Q&A magnitude:** a standard new content domain (2 tables + CRUD); the PDP
   tab slot already exists as a placeholder (one-line swap). Not a "non-trivial
   tab restructure." **Condition not met.**

Both halves share the established patterns (storage-layer idempotency,
denormalized cache, eligibility, adaptive presenters, rail rows). Default ships
as one PR.

## §2.2 Q&A module placement — DECIDED

**Q&A lives in `internal/catalog` / `catalog_schema`** (alongside reviews), per
the user. product_questions/product_answers are catalog_schema tables; product_id
FK stays in-schema, user_id is a plain BIGINT (no cross-schema FK, matching
product_reviews). No new schema bootstrap.
