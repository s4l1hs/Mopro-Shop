import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/web/mega_menu/promo_image_placeholder.dart';
import 'package:mopro_api/mopro_api.dart';

/// Full-width panel opened from `MegaMenuBar` for the active top-level
/// category.
///
/// Layout:
/// - `surface` background; 1dp `outlineVariant` border on the bottom edge so
///   the bar's bottom border continues visually.
/// - 8dp corner radius on bottom corners only (top flush with the bar).
/// - 6dp drop shadow below.
/// - Content clamped to `Breakpoints.desktopContentMax` (1240dp), centered.
/// - 24dp vertical padding; 32dp column gap; 8dp row gap.
///
/// Layout variants (Session 4d §3):
/// - `active.promoSlot == null` → 4 columns of subcategories.
/// - `active.promoSlot != null` → 3 columns of subcategories + 1 promo
///   column on the right.
/// The promo column width matches a single subcategory column for visual
/// consistency.
///
/// Empty / fallback states:
/// - If `active.children` is empty → centered fallback message.
/// - If a subcategory's leaves is empty → header only, no "Tümünü gör".
/// - Up to 8 leaves visible per column; overflow surfaces via "Tümünü gör".
/// - Broken promo image URL renders `PromoImagePlaceholder` instead of
///   propagating a Flutter error frame.
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
  static const int _columnCountWithPromo = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final subcats = active.children;
    final promo = active.promoSlot;

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
                  // When a promo is present, the subcategory grid shrinks
                  // to 3 columns and the promo column takes the 4th slot.
                  columnCount: promo != null
                      ? _columnCountWithPromo
                      : _columnCount,
                  maxLeavesPerColumn: _maxLeavesPerColumn,
                  promoColumn: promo != null
                      ? _PromoColumn(
                          promo: promo,
                          onTap: () {
                            onDismiss();
                            context.go(promo.deepLink);
                          },
                        )
                      : null,
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
    this.promoColumn,
  });

  final List<CategoryNode> subcats;
  final int columnCount;
  final int maxLeavesPerColumn;
  final ValueChanged<int> onLeafTap;
  final ValueChanged<int> onHeaderTap;
  final ValueChanged<int> onSeeAllTap;

  /// When non-null, rendered as the rightmost slot (the "+1" in 3+1).
  /// Sized identically to a subcategory column for visual consistency.
  final Widget? promoColumn;

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
          // 32dp gap between every column AND between the last subcat
          // column and the promo column (when present). No trailing gap
          // when there's no promo.
          if (i < columns.length - 1 || promoColumn != null)
            const SizedBox(width: 32),
        ],
        if (promoColumn != null) Expanded(child: promoColumn!),
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

/// The "+1" of the 3+1 mega menu layout: 16:9 image card, 2-line title,
/// full-width brand-orange CTA. Tapping anywhere (image or CTA) routes
/// to `promo.deepLink`. Broken image URLs render `PromoImagePlaceholder`
/// instead of propagating an error frame.
class _PromoColumn extends StatelessWidget {
  const _PromoColumn({required this.promo, required this.onTap});

  final CategoryPromoSlot promo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 16:9 image card.
        AspectRatio(
          aspectRatio: 16 / 9,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: CachedNetworkImage(
                  imageUrl: promo.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: cs.surfaceContainerHighest,
                  ),
                  errorWidget: (_, __, ___) => const PromoImagePlaceholder(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            promo.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: MoproTokens.primaryLight,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text('mega_menu.promo.cta'.tr()),
          ),
        ),
      ],
    );
  }
}
