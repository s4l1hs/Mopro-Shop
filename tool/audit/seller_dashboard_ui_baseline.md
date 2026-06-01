# Audit — Seller Dashboard UI (consume 5a seller backend)

Read-only baseline. file:line + observation.

## Branch-point (§1.1)
- PR #32 (5b) merged into `feat/seller-facing-and-platform-growth` (#31 slug too);
  that accumulation branch holds **5a+slug+5b** (tip `73b14dd7`) but is **NOT on
  main** (main `3234ac92`). Branched `feat/seller-dashboard-ui` off it (stacking
  precedent). `make verify` green → no §1.1 hygiene commit.

## §2.1 5a backend contracts (code-verified)
- Routes (`cmd/core-svc/main.go`): `GET /sellers/{slug}[/products|/reviews]`
  (public); `GET /seller/returns`, `POST /seller/returns/{id}/{approve,reject}`,
  `GET /seller/questions` (role-gated by `requireSellerRole`).
- `RequireSellerRole` (`internal/identity/middleware/seller.go`) → 403 `not_a_seller`
  for non-sellers; resolves seller_id into ctx via `sellerSvc.ResolveSellerForUser`.
- Response shapes (`cmd/core-svc/seller_handlers.go`):
  - returns list: `{data:[{id, order_id, status, reason, description,
    refund_amount_minor, refund_currency, created_at}], hasMore}`.
  - approve/reject → `{id, order_id, status}`. reject body `{reason_code, note?}`
    (backend accepts **any** reason_code string — no enum; client defines codes).
  - questions inbox: `{data:[{id, product_id, user_id, author_name, body,
    answer_count, created_at}], total, page, hasMore}`; `?unanswered=true` filter.
- `is_seller` on answers: `handleCreateAnswer` computes it via
  `seller.ResolveSellerForUser ∩ catalog.ProductSellerID` (5a). The existing
  `POST /products/{productId}/questions/{questionId}/answers` is what the seller
  detail screen will POST to.
- **GAP: no seller-scoped `GET /seller/returns/:id`** (5a shipped list + actions
  only). The list header has enough for the detail screen + approve/reject (which
  only need the id). Item-level breakdown would need a new seller-scoped
  detail-with-items endpoint → **out of the §3 "/me-only" scope; Backlog**. Detail
  renders from the header (status/reason/refund/description/date) found via the
  inbox provider's cached list (deep-link falls back to a list fetch + find).

## §2.2 userIsSeller data source — GATE
- `GET /me` (`auth_handlers.go:79` → `handleGetMe` → `userResponse`, line 525)
  returns id/email/phone/name/locale/mfa/timestamps — **NO seller binding**.
- Generated `User` DTO (`mopro_api/.../user.dart`): same fields, no seller.
- `currentUserProvider` (`current_user_provider.dart`) maps `MeApi.getMe()` → a
  `CurrentUser` view-model (no seller field).
- **Decision → §3.2 applies:** extend `/me` with `seller_binding` (nullable).
  Bounded: `sellerSvc` is already wired in main.go (5a); `seller_users` exists (no
  migration); add one seller `GetBindingForUser` (single JOIN) + handler enrich +
  OpenAPI/regen + `CurrentUser.sellerBinding` mapping. **§1.6 does NOT fire** (no
  auth-middleware change, no new endpoint, no migration).

## §2.3 Account rail
- `AccountLeftRail._authedRows` (`account_left_rail.dart:51`): profile, orders,
  returns, reviews, questions, wallet, addresses, cards, security, privacy,
  **history** (5b), notifications, divider, help, theme, lang, divider, logout.
- `AccountRailItem` enum + `accountRailItemFor` resolver. Add a `seller` item +
  "Satıcı Paneli" row (between questions/privacy area) gated on userIsSeller;
  resolver maps `/seller` → the new item (sub-routes inherit highlight).

## §2.4 Reusable widgets
- `qa_form_content.dart` `AnswerFormContent` (composer) + `answer_row.dart`
  `AnswerRow` (with "Satıcı" badge) — reuse directly in seller question detail.
- `ProductCard` / `ProductSummary` for thumbnails.
- Adaptive presenter (PR #17) for the reject reason sheet/dialog.

## §2.5 Route registration + redirect
- `routerProvider` (`app_router.dart:202`) — top-level `redirect:` calls
  `computeAuthRedirect(auth, location)` (pure, unit-tested). `refreshListenable`
  on auth. Extend `computeAuthRedirect` with `isSeller` + handle `/seller/*`.
- **No existing pending-snackbar** mechanism → add `pendingSnackbarProvider`
  (StateProvider<String?>) set on redirect, shown by a listener in `app.dart`
  (`MaterialApp.router`, line 55) via a ScaffoldMessenger, then cleared.

## Baselines (§1.3)
- `go test ./...` green; `flutter analyze` clean; `flutter build web` ~4.75 MB
  (5b); `flutter test` 584 pass / macOS-golden-fails Linux-baselined. Parity ~58%.

## Backend Inputs (5a contracts consumed)
The four `/seller/*` endpoints above + `RequireSellerRole` (403 non-seller) +
the answer endpoint's server-side `is_seller`. This PR adds only `/me`
`seller_binding` (§3.2).
