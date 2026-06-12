import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';

/// PLP-06: predefined quick-filter pills above the grid — one-tap toggles for
/// the common filters, wired straight to `plpFiltersProvider` (no new backend;
/// each write rebuilds the products notifier and refetches page 1).
///
/// Mobile-only by design: the wide layout already exposes these toggles in the
/// always-visible FilterPanel sidebar + the active-chip row; on mobile the
/// filters hide behind the sheet button, so one-tap pills earn their row.
///
/// Labels reuse the existing filter i18n keys (`plp.free_shipping`,
/// `catalog.filter_in_stock`, `plp.filter_price_dropped`, `plp.chip_rating`).
class PlpQuickPills extends ConsumerWidget {
  const PlpQuickPills({required this.plpKey, super.key});

  final String plpKey;

  /// The one-tap rating threshold ("4★ ve üzeri").
  static const int _quickRating = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(plpFiltersProvider(plpKey));
    final notifier = ref.read(plpFiltersProvider(plpKey).notifier);

    Widget pill({
      required String label,
      required bool selected,
      required PlpFilters Function(PlpFilters) toggle,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) =>
              notifier.update((x) => toggle(x).copyWith(page: 1)),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          pill(
            label: 'plp.free_shipping'.tr(),
            selected: f.freeShippingOnly,
            toggle: (x) => x.copyWith(freeShippingOnly: !x.freeShippingOnly),
          ),
          pill(
            label: 'plp.filter_price_dropped'.tr(),
            selected: f.priceDropped,
            toggle: (x) => x.copyWith(priceDropped: !x.priceDropped),
          ),
          pill(
            label:
                'plp.chip_rating'.tr(namedArgs: {'rating': '$_quickRating'}),
            selected: f.ratingMin == _quickRating,
            toggle: (x) => x.copyWith(
              ratingMin: x.ratingMin == _quickRating ? null : _quickRating,
            ),
          ),
          pill(
            label: 'catalog.filter_in_stock'.tr(),
            selected: f.inStock,
            toggle: (x) => x.copyWith(inStock: !x.inStock),
          ),
        ],
      ),
    );
  }
}
