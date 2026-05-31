import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/mopro_logo.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro/features/notifications/widgets/notification_badge.dart';
import 'package:mopro/shell/account_hover_menu.dart';
import 'package:mopro/shell/web_search_pill.dart';

/// Tablet + desktop top header. Full-bleed surface background with a 1dp
/// bottom border; content clamped + centered via [CenteredContentColumn].
///
/// **Session 4a scope:** logo · `WebSearchPill` (real text input with the
/// `SearchSuggestionsDropdown` anchored beneath it) · favorites/cart icons
/// with badges · guest login pill OR authed avatar, each wrapped in
/// `AccountHoverMenu` so hover reveals the menu panel.
///
/// **Still deferred:** exact 56dp tablet vs 64dp desktop split (currently
/// 64 at both); MegaMenuBar (Session 4b §4).
class WebHeader extends ConsumerWidget implements PreferredSizeWidget {
  const WebHeader({super.key});

  static const double height = 64;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark
        ? MoproTokens.borderDark
        : MoproTokens.borderLight;

    final cartCount = ref.watch(cartCountProvider);
    final favCount = ref.watch(favoritesProvider).length;
    final isAuthed =
        ref.watch(authNotifierProvider).valueOrNull is AuthAuthenticated;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SafeArea(
        bottom: false,
        child: CenteredContentColumn(
          child: Row(
            children: [
              // ── Logo (left) ─────────────────────────────────────────────
              _LogoButton(
                onTap: () => context.go('/'),
                child: const MoproLogo(
                  height: 32,
                ),
              ),
              const SizedBox(width: 24),

              // ── Search pill (center, flex with max width) ───────────────
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 320,
                    maxWidth: 720,
                  ),
                  child: const WebSearchPill(),
                ),
              ),
              const SizedBox(width: 16),

              // ── Action icons (right) ────────────────────────────────────
              _HeaderIconButton(
                icon: favCount > 0
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                badge: favCount > 0 ? favCount : null,
                tooltip: 'nav.favorites',
                onTap: () => context.go('/favorites'),
                primary: MoproTokens.primaryLight,
              ),
              const SizedBox(width: 4),
              _HeaderIconButton(
                icon: Icons.shopping_bag_outlined,
                badge: cartCount > 0 ? cartCount : null,
                tooltip: 'nav.cart',
                onTap: () => context.go('/cart'),
                primary: MoproTokens.primaryLight,
              ),
              const SizedBox(width: 8),

              // ── Account region (login pill OR avatar), wrapped in
              //    AccountHoverMenu so hover reveals the menu panel. The
              //    trigger still navigates on tap (forwarded by the menu).
              AccountHoverMenu(
                isAuthed: isAuthed,
                trigger: isAuthed
                    ? const _AccountAvatar()
                    : const _LoginPill(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Logo button (no visible chrome; just a clickable region) ─────────────────

class _LogoButton extends StatelessWidget {
  const _LogoButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: 'Mopro',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

// ── Header icon button with optional badge — 44dp hit target ─────────────────

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.primary,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color primary;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget content = Icon(icon, size: 22, color: cs.onSurface);

    if (badge != null && badge! > 0) {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge! > 99 ? '99+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: content),
        ),
      ),
    );
  }
}

// ── Guest login pill ─────────────────────────────────────────────────────────
// Visual-only trigger. Interaction (hover-open / click-toggle) is owned by
// the wrapping AccountHoverMenu.

class _LoginPill extends StatelessWidget {
  const _LoginPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: MoproTokens.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          'Giriş Yap',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ── Authed account avatar (initial-only for minimal scope) ───────────────────
// Visual-only trigger; AccountHoverMenu owns interaction.

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Account',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: NotificationBadge(
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: MoproTokens.primaryLight,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                'M',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
