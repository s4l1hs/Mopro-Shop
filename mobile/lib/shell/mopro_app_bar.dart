import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/widgets/mopro_logo.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/shell/header_search_bar.dart';
import 'package:mopro/widgets/mopro_badge.dart';

/// Trendyol-style app bar.
///
/// Layout:
///   Row 1: logo on the left, notifications + cart icons on the right
///   Row 2: full-width animated search pill
class MoproAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const MoproAppBar({
    this.showSearch = true,
    super.key,
  });

  final bool showSearch;

  static const double _toolbarH = kToolbarHeight;
  static const double _searchH = 52;

  @override
  Size get preferredSize =>
      Size.fromHeight(showSearch ? _toolbarH + _searchH : _toolbarH);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cartCount = ref.watch(cartCountProvider);

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Row 1: Logo + actions ───────────────────────────────────
            SizedBox(
              height: _toolbarH,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const MoproLogo(
                      height: 34,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, size: 24),
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 2),
                    MoproBadge(
                      count: cartCount,
                      child: IconButton(
                        icon: const Icon(
                          Icons.shopping_bag_outlined,
                          size: 24,
                        ),
                        onPressed: () => context.go('/cart'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── Row 2: Search pill ──────────────────────────────────────
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: HeaderSearchBar(
                  onTap: () => context.push('/search'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
