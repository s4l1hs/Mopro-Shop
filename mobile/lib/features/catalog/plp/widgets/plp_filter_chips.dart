import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/utils/money.dart';

/// Selected-filter chip row shown above the grid (§2.4). One chip per active
/// filter with an "×" that removes it; a "Tümünü Temizle" trailing button when
/// two or more are active. Hidden entirely when no filters are active. Each
/// chip removal writes through `plpFiltersProvider`, which the screen mirrors to
/// the URL. Chips fade in/out over 150 ms.
class PlpFilterChips extends ConsumerWidget {
  const PlpFilterChips({required this.plpKey, super.key});

  final String plpKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(plpFiltersProvider(plpKey));
    final notifier = ref.read(plpFiltersProvider(plpKey).notifier);

    final chips = <Widget>[];
    void chip(String label, PlpFilters Function(PlpFilters) remove) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InputChip(
            label: Text(label),
            onDeleted: () => notifier.update(remove),
            deleteIcon: const Icon(Icons.close, size: 16),
          ),
        ),
      );
    }

    for (final b in f.brands) {
      chip(
        'plp.chip_brand'.tr(namedArgs: {'brand': b}),
        (x) => x.copyWith(brands: x.brands.where((e) => e != b).toList()),
      );
    }
    if (f.priceMinMinor != null || f.priceMaxMinor != null) {
      final lo = f.priceMinMinor == null
          ? '0'
          : MoneyUtils.formatMinor(f.priceMinMinor!);
      final hi = f.priceMaxMinor == null
          ? '∞'
          : MoneyUtils.formatMinor(f.priceMaxMinor!);
      chip(
        'plp.chip_price'.tr(namedArgs: {'min': lo, 'max': hi}),
        (x) => x.copyWith(priceMinMinor: null, priceMaxMinor: null),
      );
    }
    if (f.ratingMin != null) {
      chip(
        'plp.chip_rating'.tr(namedArgs: {'rating': '${f.ratingMin}'}),
        (x) => x.copyWith(ratingMin: null),
      );
    }
    if (f.freeShippingOnly) {
      chip('plp.free_shipping'.tr(), (x) => x.copyWith(freeShippingOnly: false));
    }
    if (f.inStock) {
      chip('catalog.filter_in_stock'.tr(), (x) => x.copyWith(inStock: false));
    }
    if (f.priceDropped) {
      chip('plp.filter_price_dropped'.tr(),
          (x) => x.copyWith(priceDropped: false));
    }
    // PLP-13: one chip per selected attribute value (label is the value itself,
    // already localized server-side). Removal drops it from attrs[slug].
    for (final entry in f.attrs.entries) {
      final slug = entry.key;
      for (final v in entry.value) {
        chip(v, (x) {
          final next = <String, List<String>>{
            for (final e in x.attrs.entries) e.key: List<String>.from(e.value),
          };
          final list = next[slug];
          if (list != null) {
            list.remove(v);
            if (list.isEmpty) next.remove(slug);
          }
          return x.copyWith(attrs: next, page: 1);
        });
      }
    }

    final visible = chips.isNotEmpty;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: !visible
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  ...chips,
                  if (f.activeChipCount >= 2)
                    TextButton(
                      onPressed: () => notifier.set(const PlpFilters()),
                      child: Text('plp.clear_all'.tr()),
                    ),
                ],
              ),
            ),
    );
  }
}
