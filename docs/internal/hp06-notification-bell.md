# HP-06 — Global Notification Bell — discovery

> Sprint A. Mount a notification bell with the live unread badge into the mobile
> header and the desktop `WebHeader`, wired to the shipped Tranche-2a inbox
> stack. **Reuse — build no new system.** Paths verified against source on
> `feat/notification-bell-hp06`.

## Header widgets — where cart/favorites mount

- **Mobile header = `_HomeTopBar`** (`lib/features/catalog/screens/home_screen.dart:210`).
  A `Row`: `Expanded(_AnimatedSearchPill)` + (authed-only) `_CoinBalanceAction`.
  This is the *only* mobile top region. **Cart/favorites do NOT live here** — on
  mobile they sit in the always-visible bottom nav (`app_shell.dart` /
  `bottom_nav_shell.dart`). The only top-bar action is the coin pill
  (`_CoinBalanceAction`, `home_screen.dart:334`), gated `if (isAuthed)`.
- **Desktop header = `WebHeader`** (`lib/shell/web_header.dart:26`). Action row:
  `_HeaderIconButton(favorites)` → `_HeaderIconButton(cart)` → `AccountHoverMenu`
  wrapping `_AccountAvatar`. Each `_HeaderIconButton` is
  `Tooltip > InkResponse(44dp) > Icon(22, cs.onSurface)` with an optional count
  pill. Favorites/cart are **always visible** (guest included); their badge only
  renders when count > 0. Account region: guest → `_LoginPill`, authed → avatar.

## The Tranche-2a unread-count provider + badge

- **Provider:** `unreadNotificationCountProvider`
  (`lib/features/notifications/application/notifications_provider.dart:17`) —
  `NotifierProvider<UnreadCountNotifier, int>`. **Returns 0 for guests** (auth
  watched in `build()`), refreshes on-demand. Already guest-safe — no badge ever
  shows for an unauthenticated user.
- **Badge widget:** `NotificationBadge`
  (`lib/features/notifications/widgets/notification_badge.dart:9`) — wraps a child
  with the top-right overlay; **renders just the child at count ≤ 0** (dot 1–9,
  "9+" pill above 9). It already `ref.watch`es the provider internally.
- **Pre-existing mount:** `NotificationBadge` currently wraps `_AccountAvatar`
  in `WebHeader` (`web_header.dart:251`). With a dedicated bell, the badge moves
  to the bell so the unread count has **one** home (avatar keeps just the 'M').

## Inbox route (destination — EXISTS, no DEFER)

- `GoRoute('/account/notifications')` → `NotificationsScreen`
  (`lib/core/router/app_router.dart:597`). Screen handles loading/error/empty
  gracefully. **Not** in the `hardGated` redirect list (`app_router.dart:196`),
  so a guest tap lands on the screen (empty/soft-error), not a login bounce.

## Gating pattern to mirror

- Desktop cart/favorites = **always visible**, badge hidden at 0, tap navigates.
  Mobile coin pill = authed-only (shows personal balance).
- **Decision:** the bell mirrors **cart/favorites** — *always visible* on both
  surfaces, the personal part (unread badge) auto-hidden at count 0 (guests = 0).
  Satisfies "auth-gated like cart/favorites" + anti-goal #2 (no guest badge)
  without inventing a new auth hook, and makes both guest goldens flip as
  predicted. Guest tap → notifications screen (graceful empty), like guest→/cart.

## Plan (one commit per concern)

1. `NotificationBell` widget — bell icon overlaid with `NotificationBadge`,
   `Tooltip`/`Semantics`, 44dp hit target, `onTap` supplied by the caller
   (mirrors `_HeaderIconButton`). Theme tokens, no hardcoded colors.
2. Mount in `_HomeTopBar` (mobile), before the authed coin pill.
3. Mount in `WebHeader` (desktop) adjacent to cart; drop the redundant
   `NotificationBadge` from `_AccountAvatar`.
4. i18n: `notifications.bell_tooltip` (TR + EN).
5. Goldens: `web_header_*` (3) + `home_*` (mobile/tablet/desktop) flip — regen on
   Linux via `golden-rebaseline.yml`.

## Test reality

- `web_header_test.dart` + `home_goldens_5a_test.dart` both pump as **guest**
  (`AuthUnauthenticated`). Always-visible bell ⇒ both flip. Goldens stub the
  provider via `test/_support/stub_unread_count.dart` (`stubUnreadCountOverride`,
  returns 0) — so the bell renders with **no** badge in every golden.
