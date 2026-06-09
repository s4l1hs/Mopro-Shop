import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/plp/widgets/plp_facets.dart';

/// Mobile PLP filter bottom sheet (PLP-01). **Provider-backed** — every control
/// applies live to `plpFiltersProvider(plpKey)` (same semantics as the desktop
/// sidebar), so the result count + removable chips reflect immediately and the
/// state round-trips to the URL. Surfaces **Brand (searchable) + Rating**
/// accordions — reusing [PlpBrandFacet]/[PlpRatingFacet] — alongside price,
/// free-shipping and in-stock.
Future<void> showPlpFilterSheet(
  BuildContext context, {
  required String plpKey,
  required List<String> brands,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => PlpFilterSheet(plpKey: plpKey, brands: brands),
  );
}

class PlpFilterSheet extends ConsumerStatefulWidget {
  const PlpFilterSheet({required this.plpKey, required this.brands, super.key});

  final String plpKey;
  final List<String> brands;

  @override
  ConsumerState<PlpFilterSheet> createState() => _PlpFilterSheetState();
}

class _PlpFilterSheetState extends ConsumerState<PlpFilterSheet> {
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  PlpFiltersNotifier get _notifier =>
      ref.read(plpFiltersProvider(widget.plpKey).notifier);

  @override
  void initState() {
    super.initState();
    final f = ref.read(plpFiltersProvider(widget.plpKey));
    if (f.priceMinMinor != null) {
      _minCtrl.text = (f.priceMinMinor! ~/ 100).toString();
    }
    if (f.priceMaxMinor != null) {
      _maxCtrl.text = (f.priceMaxMinor! ~/ 100).toString();
    }
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = ref.watch(plpFiltersProvider(widget.plpKey));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'catalog.filter_title'.tr(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _minCtrl.clear();
                      _maxCtrl.clear();
                      _notifier.set(const PlpFilters());
                    },
                    child: Text('catalog.filter_reset'.tr()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Brand (searchable) accordion — reuses the desktop facet.
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('plp.filter_brand'.tr()),
                    initiallyExpanded: filters.brands.isNotEmpty,
                    children: [
                      PlpBrandFacet(plpKey: widget.plpKey, brands: widget.brands),
                    ],
                  ),
                  // Rating accordion — reuses the desktop facet.
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('plp.filter_rating'.tr()),
                    initiallyExpanded: filters.ratingMin != null,
                    children: [PlpRatingFacet(plpKey: widget.plpKey)],
                  ),
                  const Divider(),
                  Text(
                    'catalog.filter_price_range'.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _priceField(_minCtrl, 'catalog.filter_min_price', true),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _priceField(_maxCtrl, 'catalog.filter_max_price', false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('catalog.filter_free_shipping'.tr()),
                    value: filters.freeShippingOnly,
                    onChanged: (v) =>
                        _notifier.update((f) => f.copyWith(freeShippingOnly: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('catalog.filter_in_stock'.tr()),
                    value: filters.inStock,
                    onChanged: (v) =>
                        _notifier.update((f) => f.copyWith(inStock: v)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text('catalog.filter_apply'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceField(TextEditingController ctrl, String labelKey, bool isMin) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: labelKey.tr(), prefixText: '₺'),
      onChanged: (raw) {
        final tl = int.tryParse(raw.trim());
        final minor = tl == null ? null : tl * 100;
        _notifier.update(
          (f) => isMin
              ? f.copyWith(priceMinMinor: minor, page: 1)
              : f.copyWith(priceMaxMinor: minor, page: 1),
        );
      },
    );
  }
}
