import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/filtered_products_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// PLP breadcrumb trail (PLP-05). Builds the category ancestry client-side from
/// `categoriesProvider` (walks `Category.parentId` to the root) — no API change.
/// `Anasayfa › Root › … › Current`; ancestors tap to their category, the current
/// crumb is plain. Hidden until the category tree is available.
class PlpBreadcrumb extends ConsumerWidget {
  const PlpBreadcrumb({required this.categoryId, super.key});

  final int categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).categories.valueOrNull ?? const [];
    if (cats.isEmpty) return const SizedBox.shrink();
    final byId = {for (final c in cats) c.id: c};

    // Walk parents from the current category up to the root.
    final chain = <Category>[];
    int? id = categoryId;
    final seen = <int>{};
    while (id != null && byId.containsKey(id) && seen.add(id)) {
      final c = byId[id]!;
      chain.insert(0, c);
      id = c.parentId;
    }
    if (chain.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodySmall;
    final link = base?.copyWith(color: cs.onSurfaceVariant);
    final current = base?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
    );

    final items = <Widget>[
      _crumb('plp.breadcrumb_home'.tr(), link, () => context.go('/')),
    ];
    for (var i = 0; i < chain.length; i++) {
      final c = chain[i];
      final isLast = i == chain.length - 1;
      items
        ..add(_sep(cs))
        ..add(
          _crumb(
            c.name,
            isLast ? current : link,
            isLast ? null : () => context.go('/categories/${c.id}', extra: c.name),
          ),
        );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  Widget _crumb(String label, TextStyle? style, VoidCallback? onTap) {
    final text = Text(label, style: style, maxLines: 1);
    if (onTap == null) return text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: text,
      ),
    );
  }

  Widget _sep(ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.chevron_right, size: 14, color: cs.outline),
      );
}

/// PLP result count (PLP-04): "N ürün" from `pagination.total` (now surfaced on
/// `ProductsState.total`). Live — the provider refetches on every filter change.
/// Hidden until the first page lands.
class PlpResultCount extends ConsumerWidget {
  const PlpResultCount({required this.plpKey, super.key});

  final String plpKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(filteredProductsProvider(plpKey)).total;
    if (total == null) return const SizedBox.shrink();
    return Text(
      'plp.result_count'.tr(args: ['$total']),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
