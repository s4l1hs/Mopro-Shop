import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/shell/web_header.dart';

/// Adaptive root shell.
///
/// - Mobile (<600): existing 5-tab bottom navigation, untouched.
/// - Tablet (600..<1024) and desktop (≥1024): no bottom nav; `WebHeader`
///   pinned at top via a Scaffold appBar. The actual top-region content
///   (logo / search / icons) lives in [WebHeader] (§4 fills it in).
class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveBuilder(
      mobile: (_) => _MobileShell(navigationShell: navigationShell),
      tablet: (_) => _WebShell(navigationShell: navigationShell),
      desktop: (_) => _WebShell(navigationShell: navigationShell),
    );
  }
}

// ── Mobile shell (unchanged from Session 1) ───────────────────────────────────

class _MobileShell extends ConsumerWidget {
  const _MobileShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  void _branch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cartCount = ref.watch(cartCountProvider);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final surface = theme.colorScheme.surface;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: surface,
          border: Border(
            top: BorderSide(
              color: isDark ? MoproTokens.borderDark : MoproTokens.borderLight,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _NavItem(
                  index: 0,
                  currentIndex: navigationShell.currentIndex,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'nav.home'.tr(),
                  primary: primary,
                  muted: muted,
                  onTap: () => _branch(0),
                ),
                _NavItem(
                  index: 1,
                  currentIndex: navigationShell.currentIndex,
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view,
                  label: 'nav.categories'.tr(),
                  primary: primary,
                  muted: muted,
                  onTap: () => _branch(1),
                ),
                _NavItem(
                  index: 2,
                  currentIndex: navigationShell.currentIndex,
                  icon: Icons.favorite_border_rounded,
                  activeIcon: Icons.favorite_rounded,
                  label: 'nav.favorites'.tr(),
                  primary: primary,
                  muted: muted,
                  onTap: () => _branch(2),
                ),
                _NavItem(
                  index: 3,
                  currentIndex: navigationShell.currentIndex,
                  icon: Icons.shopping_bag_outlined,
                  activeIcon: Icons.shopping_bag,
                  label: 'nav.cart'.tr(),
                  primary: primary,
                  muted: muted,
                  badge: cartCount > 0 ? cartCount : null,
                  onTap: () => _branch(3),
                ),
                _NavItem(
                  index: 4,
                  currentIndex: navigationShell.currentIndex,
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'nav.account'.tr(),
                  primary: primary,
                  muted: muted,
                  onTap: () => _branch(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tablet + desktop shell — WebHeader pinned, no bottom nav ─────────────────

class _WebShell extends StatelessWidget {
  const _WebShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WebHeader(),
      body: navigationShell,
    );
  }
}

// ── Mobile bottom-nav item (unchanged) ────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.primary,
    required this.muted,
    required this.onTap,
    this.badge,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color primary;
  final Color muted;
  final int? badge;
  final VoidCallback onTap;

  bool get _selected => index == currentIndex;

  @override
  Widget build(BuildContext context) {
    final color = _selected ? primary : muted;

    Widget iconWidget = Icon(
      _selected ? activeIcon : icon,
      size: 24,
      color: color,
    );

    if (badge != null && badge! > 0) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    _selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
