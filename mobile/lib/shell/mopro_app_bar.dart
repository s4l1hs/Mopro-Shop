import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/shell/header_search_bar.dart';
import 'package:mopro/widgets/theme_toggle.dart';

/// Standard Mopro app bar with logo, search pill, and theme toggle.
/// Use as `appBar: MoproAppBar()` — it implements [PreferredSizeWidget].
class MoproAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MoproAppBar({
    this.showSearch = true,
    this.showThemeToggle = true,
    super.key,
  });

  final bool showSearch;
  final bool showThemeToggle;

  @override
  Size get preferredSize =>
      Size.fromHeight(showSearch ? kToolbarHeight + 56 : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return AppBar(
      titleSpacing: 16,
      title: _MoproLogo(theme: theme),
      actions: [
        if (showThemeToggle) const ThemeToggle(),
        const SizedBox(width: 8),
      ],
      bottom: showSearch
          ? PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: HeaderSearchBar(
                  onTap: () => context.push('/search'),
                ),
              ),
            )
          : null,
      surfaceTintColor: Colors.transparent,
      backgroundColor: cs.surface,
    );
  }
}

class _MoproLogo extends StatelessWidget {
  const _MoproLogo({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.shopping_bag,
            size: 16,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Mopro',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
