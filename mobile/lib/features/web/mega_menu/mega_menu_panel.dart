import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';

/// Full-width panel opened from `MegaMenuBar` for the active top-level
/// category. Session 4c §4 ships the 4-column layout only; the optional
/// `3-columns + promo` variant is deferred to Session 4d (needs the
/// `promo_slot` JSONB column + migration 0067).
///
/// Layout:
/// - `surface` background; 1dp `outlineVariant` border on the bottom edge so
///   the bar's bottom border continues visually.
/// - 8dp corner radius on bottom corners only (top flush with the bar).
/// - 6dp drop shadow below.
/// - Content clamped to `Breakpoints.desktopContentMax` (1240dp), centered.
/// - 24dp vertical padding; 32dp column gap; 8dp row gap.
///
/// Empty / fallback states:
/// - If `active.children` is empty → centered fallback message.
/// - If a subcategory's leaves is empty → header only, no "Tümünü gör".
/// - Up to 8 leaves visible per column; overflow surfaces via "Tümünü gör".
class MegaMenuPanel extends StatelessWidget {
  const MegaMenuPanel({
    required this.active,
    required this.onDismiss,
    super.key,
  });

  final CategoryNode active;
  final VoidCallback onDismiss;

  static const int _maxLeavesPerColumn = 8;
  static const int _columnCount = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final subcats = active.children;

    return Material(
      elevation: 6,
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(8),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(8),
          ),
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant),
            left: BorderSide(color: cs.outlineVariant),
            right: BorderSide(color: cs.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: CenteredContentColumn(
          child: subcats.isEmpty
              ? _EmptyState()
              : _ColumnGrid(
                  subcats: subcats,
                  columnCount: _columnCount,
                  maxLeavesPerColumn: _maxLeavesPerColumn,
                  onLeafTap: (id) {
                    onDismiss();
                    context.go('/categories/$id');
                  },
                  onHeaderTap: (id) {
                    onDismiss();
                    context.go('/categories/$id');
                  },
                  onSeeAllTap: (id) {
                    onDismiss();
                    context.go('/categories/$id');
                  },
                ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'mega_menu.empty_children'.tr(),
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ColumnGrid extends StatelessWidget {
  const _ColumnGrid({
    required this.subcats,
    required this.columnCount,
    required this.maxLeavesPerColumn,
    required this.onLeafTap,
    required this.onHeaderTap,
    required this.onSeeAllTap,
  });

  final List<CategoryNode> subcats;
  final int columnCount;
  final int maxLeavesPerColumn;
  final ValueChanged<int> onLeafTap;
  final ValueChanged<int> onHeaderTap;
  final ValueChanged<int> onSeeAllTap;

  @override
  Widget build(BuildContext context) {
    // Distribute subcategories across `columnCount` columns left-to-right.
    final columns = <List<CategoryNode>>[
      for (var i = 0; i < columnCount; i++) <CategoryNode>[],
    ];
    for (var i = 0; i < subcats.length; i++) {
      columns[i % columnCount].add(subcats[i]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          Expanded(
            child: _SubcatColumn(
              entries: columns[i],
              maxLeavesPerColumn: maxLeavesPerColumn,
              onLeafTap: onLeafTap,
              onHeaderTap: onHeaderTap,
              onSeeAllTap: onSeeAllTap,
            ),
          ),
          if (i < columns.length - 1) const SizedBox(width: 32),
        ],
      ],
    );
  }
}

class _SubcatColumn extends StatelessWidget {
  const _SubcatColumn({
    required this.entries,
    required this.maxLeavesPerColumn,
    required this.onLeafTap,
    required this.onHeaderTap,
    required this.onSeeAllTap,
  });

  final List<CategoryNode> entries;
  final int maxLeavesPerColumn;
  final ValueChanged<int> onLeafTap;
  final ValueChanged<int> onHeaderTap;
  final ValueChanged<int> onSeeAllTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final subcat in entries) ...[
          _SubcatHeader(node: subcat, onTap: () => onHeaderTap(subcat.id)),
          for (final leaf
              in subcat.children.take(maxLeavesPerColumn))
            _LeafRow(node: leaf, onTap: () => onLeafTap(leaf.id)),
          if (subcat.children.length > maxLeavesPerColumn)
            _SeeAllLink(onTap: () => onSeeAllTap(subcat.id)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _SubcatHeader extends StatelessWidget {
  const _SubcatHeader({required this.node, required this.onTap});
  final CategoryNode node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          node.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LeafRow extends StatelessWidget {
  const _LeafRow({required this.node, required this.onTap});
  final CategoryNode node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          node.name,
          style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'mega_menu.see_all'.tr(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MoproTokens.primaryLight,
          ),
        ),
      ),
    );
  }
}
