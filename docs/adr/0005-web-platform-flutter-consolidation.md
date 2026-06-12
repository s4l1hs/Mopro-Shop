# ADR 0005: Web Platform Consolidation onto Flutter

- **Status:** Accepted
- **Date:** 2026-06-12
- **Phase introduced:** Parity / platform-consolidation
- **Decided by:** Salih (project owner) — supersedes the implicit "web = Next.js" choice
- **Related:** CLAUDE.md § 2.2 (no new languages), § 8 (tech-stack lock), ARCHITECTURE.md, the Next.js `web/` app

## Context

The repo carried **two** front-end codebases:

1. **`mobile/`** — the Flutter app. It is the canonical UI and is already
   **responsive with desktop/web chrome** (`lib/features/web/mega_menu/`,
   `lib/shell/web_header.dart`) and **web SEO helpers** (`seo_head.dart`,
   `meta_tags_service_web.dart`, `structured_data_service_web.dart`). The Flutter
   **web build target is already enabled** (`mobile/web/index.html`,
   `manifest.json`, icons). Every Trendyol-parity finding in the audits was
   implemented here.
2. **`web/`** — a Next.js 15 / TypeScript app: SSR product/category/search pages,
   `[locale]` routing, and server BFF routes under `web/app/api/`
   (`payments/{intent,status}`, `auth/{refresh,logout,otp-request,otp-verify}`)
   that wrapped the Go backend behind httpOnly cookies.

Two material facts drove this decision:

- **The Next.js app was never deployed.** `deploy/caddy/Caddyfile` serves
  `moproshop.com` / `www` as a `"Çok yakında / Coming soon"` placeholder — there
  is **no reverse-proxy to a Next.js process anywhere** in the routing. The web/
  app ran only locally; production has no SSR web tier to decommission.
- **The Flutter client talks to the Go backend directly** (Caddy →
  `core-svc`/`fin-svc`), exactly as the mobile app does. The Next.js BFF routes
  existed only because SSR used server-side cookies; a Flutter web client uses
  the same bearer-token auth as mobile, so those routes have **no consumer** once
  Flutter Web is the web front-end.

Maintaining two UIs (Dart + TypeScript), two i18n systems, two component
libraries, two test stacks (flutter_test + vitest/playwright), and re-doing every
parity finding twice is the ongoing cost the project no longer wants to pay.

## Decision

**Consolidate the web front-end onto Flutter Web. The Flutter app in `mobile/`
is the single UI for mobile *and* web. Remove the Next.js `web/` app.**

- Web is served as the **release Flutter Web build** (`flutter build web`),
  static-hosted by the existing Caddy at `moproshop.com` / `www` (replacing the
  Coming-soon placeholder) with SPA fallback to `index.html`.
- The Go backend (`core-svc`/`fin-svc`) is unchanged and remains the single API;
  the web client calls it through Caddy exactly like mobile.
- The Next.js BFF routes are **not migrated** — they have no consumer. (The Go
  backend already owns `/auth/*` and `/payments/*`; that is what the Flutter
  client uses today.)
- **CLAUDE.md § 8** is updated to add **Flutter (Web) — `flutter build web`** as
  the web layer; **§ 2.2** "Mobile is Flutter only" is broadened to "**all
  client UI is Flutter only**." TypeScript/Next.js is removed from the stack.

## Consequences

### Accepted trade-off — SEO / SSR

Flutter Web renders client-side (CanvasKit/HTML), which crawlers index more
weakly than Next.js SSR. We accept this. Mitigations, in order of effort:

1. Ship the existing runtime SEO helpers (`seo_head` injects `<title>`/meta,
   `structured_data_service_web` injects JSON-LD into the DOM) — modern
   Googlebot executes JS and can index a rendered SPA.
2. Keep `sitemap.xml` + `robots.txt` served by the backend/Caddy.
3. **Escape hatch (future ADR if organic traffic demands it):** add a narrow
   prerender/SSG tier *only* for product/category pages (e.g. a prerender proxy
   or a thin static-generation step) — without reviving a full parallel app.

### Positive

- One UI codebase, one i18n (`easy_localization`), one component set, one test
  stack. Parity work is done once. ~154 `web/` files removed.
- No new runtime tier on the single VDS — Caddy already runs; it gains a
  `file_server` root. Memory budget (CLAUDE.md § 7) is unaffected.

### Migration (phased; deploy deferred per project convention)

1. **This change:** ADR; validate `flutter build web`; Caddy serves the build at
   `moproshop.com`; remove `web/`; drop the web CI (`e2e.yml`); update
   CLAUDE.md/docs/ARCHITECTURE; ledger.
2. **Deploy cutover (separate, gated):** CI builds `mobile/build/web` and ships
   it to the VDS (Caddy volume); flip `moproshop.com` from placeholder to the
   `file_server` block; verify CloudFlare caching of static assets.
3. **SEO watch:** monitor Search Console after cutover; trigger the prerender
   escape hatch only if product-page indexing regresses materially.

## Alternatives considered

- **Keep Next.js for an SEO shell + Flutter Web for the app** — rejected: doubles
  the surface again for a benefit that the runtime SEO helpers + the future
  prerender escape hatch can cover if/when needed.
- **Redesign Next.js toward Trendyol, keep TypeScript** — rejected: the Trendyol
  parity already lives in Flutter; this would re-fork the work the project is
  trying to stop forking.
