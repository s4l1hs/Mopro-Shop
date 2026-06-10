import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro_api/mopro_api.dart';

/// Web-only suggestions surface shown beneath the header search pill.
///
/// Pure presentation: caller passes data + callbacks; this widget renders the
/// sections. While the user is typing (a non-empty query) it shows structured
/// brand + product suggestions (SE-06); otherwise it shows recent searches,
/// trending queries, and category shortcuts. Empty sections collapse (their
/// header is hidden). Trending and the active-query suggestions show a skeleton
/// while loading; recent/categories render synchronously from the caller.
///
/// Keyboard nav is handled by the host (WebSearchPill): each row is wrapped in
/// `Focus`/`Actions` and reachable via Tab/arrow keys, with Enter activating.
class SearchSuggestionsDropdown extends StatelessWidget {
  const SearchSuggestionsDropdown({
    required this.recentSearches,
    required this.trendingSearches,
    required this.categories,
    required this.onSelectRecent,
    required this.onSelectTrending,
    required this.onSelectCategory,
    required this.onRemoveRecent,
    super.key,
    this.brandSuggestions = const [],
    this.productSuggestions = const [],
    this.suggestionsLoading = false,
    this.onSelectBrand,
    this.onSelectProduct,
    this.maxHeight = 480,
  });

  final List<String> recentSearches;
  final AsyncSnapshot<List<String>> trendingSearches;
  final List<Category> categories;

  /// SE-06: structured brand + product suggestions for the active query. When
  /// either is non-empty (or [suggestionsLoading] is true) these replace the
  /// recent/trending/category sections — mirroring Trendyol's autocomplete.
  final List<BrandSuggestion> brandSuggestions;
  final List<ProductSummary> productSuggestions;
  final bool suggestionsLoading;

  final ValueChanged<String> onSelectRecent;
  final ValueChanged<String> onSelectTrending;
  final ValueChanged<int> onSelectCategory;
  final ValueChanged<String> onRemoveRecent;

  /// Brand tap → brand-filtered listing (host routes by name). Product tap →
  /// PDP (host routes by id). Null disables the section.
  final ValueChanged<String>? onSelectBrand;
  final ValueChanged<int>? onSelectProduct;

  final double maxHeight;

  static const int _trendingMax = 6;
  static const int _categoryShortcutMax = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final hasBrands = brandSuggestions.isNotEmpty && onSelectBrand != null;
    final hasProducts =
        productSuggestions.isNotEmpty && onSelectProduct != null;
    // The active-query mode owns the dropdown the moment a fetch is in flight or
    // returns anything, so stale recent/trending rows don't flash beneath it.
    final showSuggestions = suggestionsLoading || hasBrands || hasProducts;

    final hasRecent = recentSearches.isNotEmpty;
    final hasTrendingData = trendingSearches.data?.isNotEmpty ?? false;
    final hasTrendingLoading = trendingSearches.connectionState ==
        ConnectionState.waiting;
    final showTrendingSection = hasTrendingData || hasTrendingLoading;
    final hasCategories = categories.isNotEmpty;

    if (!showSuggestions &&
        !hasRecent &&
        !showTrendingSection &&
        !hasCategories) {
      return const SizedBox.shrink();
    }

    final List<Widget> children;
    if (showSuggestions) {
      children = [
        if (hasBrands)
          _BrandsSection(
            brands: brandSuggestions,
            onSelect: onSelectBrand!,
          ),
        if (hasProducts)
          _ProductsSection(
            products: productSuggestions,
            onSelect: onSelectProduct!,
          ),
        // No brands and no products yet, but a fetch is in flight → skeletons.
        if (!hasBrands && !hasProducts && suggestionsLoading)
          ...List.generate(4, (_) => const _SkeletonRow()),
      ];
    } else {
      children = [
        if (hasRecent)
          _RecentSection(
            queries: recentSearches,
            onSelect: onSelectRecent,
            onRemove: onRemoveRecent,
          ),
        if (showTrendingSection)
          _TrendingSection(
            snapshot: trendingSearches,
            onSelect: onSelectTrending,
            limit: _trendingMax,
          ),
        if (hasCategories)
          _CategoriesSection(
            categories: categories.take(_categoryShortcutMax).toList(),
            onSelect: onSelectCategory,
          ),
      ];
    }

    return Material(
      elevation: 4,
      color: cs.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? MoproTokens.borderDark : MoproTokens.borderLight,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

// ── Section wrappers ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.queries,
    required this.onSelect,
    required this.onRemove,
  });

  final List<String> queries;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('search.recent_searches'.tr()),
        for (final q in queries)
          _SuggestionRow(
            icon: Icons.history,
            label: q,
            onTap: () => onSelect(q),
            trailing: _RemoveButton(onTap: () => onRemove(q)),
          ),
      ],
    );
  }
}

class _TrendingSection extends StatelessWidget {
  const _TrendingSection({
    required this.snapshot,
    required this.onSelect,
    required this.limit,
  });

  final AsyncSnapshot<List<String>> snapshot;
  final ValueChanged<String> onSelect;
  final int limit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('search.trending'.tr()),
        if (snapshot.connectionState == ConnectionState.waiting)
          ...List.generate(3, (_) => const _SkeletonRow())
        else
          for (final q in snapshot.data!.take(limit))
            _SuggestionRow(
              icon: Icons.trending_up,
              label: q,
              onTap: () => onSelect(q),
            ),
      ],
    );
  }
}

class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({
    required this.categories,
    required this.onSelect,
  });

  final List<Category> categories;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('search.suggested_categories'.tr()),
        for (final c in categories)
          _CategoryRow(category: c, onTap: () => onSelect(c.id)),
      ],
    );
  }
}

class _BrandsSection extends StatelessWidget {
  const _BrandsSection({required this.brands, required this.onSelect});

  final List<BrandSuggestion> brands;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('search.brands'.tr()),
        for (final b in brands)
          _SuggestionRow(
            icon: Icons.sell_outlined,
            label: b.name,
            onTap: () => onSelect(b.name),
          ),
      ],
    );
  }
}

class _ProductsSection extends StatelessWidget {
  const _ProductsSection({required this.products, required this.onSelect});

  final List<ProductSummary> products;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('search.products'.tr()),
        for (final p in products)
          _ProductRow(product: p, onTap: () => onSelect(p.id)),
      ],
    );
  }
}

// ── Row primitives ──────────────────────────────────────────────────────────

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = category.iconUrl;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: icon == null || icon.isEmpty
                  ? Icon(
                      Icons.category_outlined,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    )
                  : ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: icon,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.category_outlined,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_forward, size: 14, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onTap});

  final ProductSummary product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final image = product.coverImageUrl;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 36,
                height: 36,
                child: image == null || image.isEmpty
                    ? ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_outlined,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.title,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.brand.isNotEmpty)
                    Text(
                      product.brand,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              MoneyUtils.formatMinor(
                product.priceMinor,
                currency: product.priceCurrency,
              ),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'search.clear_recent'.tr(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
