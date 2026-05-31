import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/design/widgets/skip_to_content_link.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_bar.dart';
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

// ── Mobile shell (unchanged from Session 1) ─────────────────────────────────

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
//
// `MegaMenuBar` (Session 4c) mounts directly under the WebHeader at `>=768`
// widths only. Below 768dp the bar is NOT in the widget tree — small tablets
// reach categories via the dedicated `/categories` route. The 768 threshold
// is enforced HERE in the shell rather than inside the bar so the bar's own
// rendering stays breakpoint-agnostic.

class _WebShell extends StatefulWidget {
  const _WebShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const double megaMenuMinWidth = 768;

  @override
  State<_WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<_WebShell> {
  // Focus scope wrapping the route content; the skip link moves focus here.
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'main-content');

  @override
  void dispose() {
    _contentScope.dispose();
    super.dispose();
  }

  void _skipToContent() {
    // Land on the first focusable descendant of the content.
    _contentScope
      ..requestFocus()
      ..nextFocus();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showMegaMenu = width >= _WebShell.megaMenuMinWidth;
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Stack(
        children: [
          MainContentScope(
            contentScope: _contentScope,
            child: Scaffold(
              appBar: const WebHeader(),
              body: Column(
                children: [
                  if (showMegaMenu) const MegaMenuBar(),
                  Expanded(
                    child: FocusScope(
                      node: _contentScope,
                      child: widget.navigationShell,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Skip link paints on top (last child) but is traversal-priority 0.
          Positioned(
            top: 8,
            left: 8,
            child: SkipToContentLink(onSkip: _skipToContent),
          ),
        ],
      ),
    );
  }
}

/// Exposes the shell's main-content focus scope to descendants (mirrors the
/// AccountChromeScope pattern). Routes may target this scope to receive focus
/// from the skip link; the default skip behaviour focuses its first focusable.
class MainContentScope extends InheritedWidget {
  const MainContentScope({
    required this.contentScope,
    required super.child,
    super.key,
  });

  final FocusScopeNode contentScope;

  static FocusScopeNode? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MainContentScope>()
      ?.contentScope;

  @override
  bool updateShouldNotify(MainContentScope oldWidget) =>
      oldWidget.contentScope != contentScope;
}

// ── Mobile bottom-nav item (unchanged) ──────────────────────────────────────

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
