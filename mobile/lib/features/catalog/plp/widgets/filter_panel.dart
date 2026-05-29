import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';

/// Desktop/tablet PLP sidebar filter panel (§2.2). Consumes the 5a substrate:
/// reads and writes `plpFiltersProvider(plpKey)` per section; all writes flow
/// through the same debounced URL update the bottom sheets use. Brand counts are
/// omitted (no aggregation endpoint yet — REPORT backlog); brands are sourced
/// from [brands] (distinct brands of the current result set).
class FilterPanel extends ConsumerStatefulWidget {
  const FilterPanel({
    required this.plpKey,
    required this.currentCategoryId,
    this.brands = const [],
    super.key,
  });

  final String plpKey;
  final int currentCategoryId;
  final List<String> brands;

  /// Slider domain ceiling when no price aggregate is available (minor units).
  static const int priceCeilingMinor = 1000000;

  @override
  ConsumerState<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends ConsumerState<FilterPanel> {
  final _brandQuery = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  bool _showAllBrands = false;
  RangeValues? _draftPrice;

  PlpFiltersNotifier get _notifier =>
      ref.read(plpFiltersProvider(widget.plpKey).notifier);

  @override
  void dispose() {
    _brandQuery.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(plpFiltersProvider(widget.plpKey));
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _section('plp.filter_category', _categoryTree(cs)),
              const Divider(height: 1),
              _section('plp.filter_brand', _brandList(filters)),
              const Divider(height: 1),
              _section('plp.filter_price', _priceRange(filters)),
              const Divider(height: 1),
              _section('plp.filter_rating', _ratingGroup(filters, cs)),
              const Divider(height: 1),
              _section('plp.filter_shipping', _freeShipping(filters)),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _brandQuery.clear();
                    _minCtrl.clear();
                    _maxCtrl.clear();
                    setState(() => _draftPrice = null);
                    _notifier.set(const PlpFilters());
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.primary),
                    foregroundColor: cs.primary,
                  ),
                  child: Text('plp.clear_all'.tr()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  // No-op in the URL-debounced model — state is already applied
                  // as the user changes filters (documented in REPORT §2.3).
                  onPressed: () {},
                  child: Text('plp.apply'.tr()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String titleKey, Widget body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            titleKey.tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        body,
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Category tree ─────────────────────────────────────────────────────────
  Widget _categoryTree(ColorScheme cs) {
    final cats = ref.watch(categoriesProvider).categories.valueOrNull ?? [];
    if (cats.isEmpty) return const SizedBox.shrink();
    final roots = cats.where((c) => c.parentId == null).toList();
    return Column(
      children: [
        for (final c in roots)
          () {
            final selected = c.id == widget.currentCategoryId;
            return InkWell(
              onTap: () =>
                  context.push('/categories/${c.id}', extra: c.name),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: selected ? cs.primary : Colors.transparent,
                      width: 4,
                    ),
                  ),
                ),
                child: Text(
                  c.name,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? cs.primary : null,
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }

  // ── Brand list ────────────────────────────────────────────────────────────
  Widget _brandList(PlpFilters filters) {
    final q = _brandQuery.text.trim().toLowerCase();
    final all = widget.brands.where((b) => b.toLowerCase().contains(q)).toList();
    final visible = (_showAllBrands || q.isNotEmpty) ? all : all.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: TextField(
            controller: _brandQuery,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 16),
              hintText: 'plp.brand_search'.tr(),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
        for (final b in visible)
          _DenseCheckbox(
            label: b,
            value: filters.brands.contains(b),
            onChanged: (checked) {
              final next = [...filters.brands];
              if (checked) {
                next.add(b);
              } else {
                next.remove(b);
              }
              next.sort(); // alphabetical for URL determinism
              _notifier.update((f) => f.copyWith(brands: next, page: 1));
            },
          ),
        if (!_showAllBrands && q.isEmpty && all.length > 8)
          TextButton(
            onPressed: () => setState(() => _showAllBrands = true),
            child: Text('plp.show_more'.tr()),
          ),
      ],
    );
  }

  // ── Price range ───────────────────────────────────────────────────────────
  Widget _priceRange(PlpFilters filters) {
    const ceil = FilterPanel.priceCeilingMinor;
    final lo =
        (filters.priceMinMinor ?? 0).toDouble().clamp(0.0, ceil.toDouble());
    final hi =
        (filters.priceMaxMinor ?? ceil).toDouble().clamp(0.0, ceil.toDouble());
    final values = _draftPrice ?? RangeValues(lo, hi);

    return Column(
      children: [
        RangeSlider(
          values: values,
          max: ceil.toDouble(),
          divisions: 100,
          labels: RangeLabels(
            '₺${(values.start / 100).round()}',
            '₺${(values.end / 100).round()}',
          ),
          onChanged: (v) => setState(() => _draftPrice = v),
          onChangeEnd: (v) {
            setState(() => _draftPrice = null);
            _notifier.update(
              (f) => f.copyWith(
                priceMinMinor: v.start <= 0 ? null : v.start.round(),
                priceMaxMinor: v.end >= ceil ? null : v.end.round(),
                page: 1,
              ),
            );
          },
        ),
        Row(
          children: [
            Expanded(child: _priceField(_minCtrl, 'plp.price_min', true, ceil)),
            const SizedBox(width: 8),
            Expanded(child: _priceField(_maxCtrl, 'plp.price_max', false, ceil)),
          ],
        ),
      ],
    );
  }

  Widget _priceField(
    TextEditingController ctrl,
    String hintKey,
    bool isMin,
    int ceil,
  ) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintKey.tr(),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onSubmitted: (raw) {
          final tl = int.tryParse(raw.trim());
          final minor = tl == null ? null : (tl * 100).clamp(0, ceil);
          _notifier.update(
            (f) => isMin
                ? f.copyWith(priceMinMinor: minor, page: 1)
                : f.copyWith(priceMaxMinor: minor, page: 1),
          );
        },
      ),
    );
  }

  // ── Rating ────────────────────────────────────────────────────────────────
  Widget _ratingGroup(PlpFilters filters, ColorScheme cs) {
    // Custom radio (Icon) to avoid the deprecated Radio.groupValue/onChanged
    // API — the project-wide Radio→RadioGroup migration is a separate backlog.
    Widget tile(int? rating, String label) {
      final selected = filters.ratingMin == rating;
      return InkWell(
        onTap: () => _notifier.update((f) => f.copyWith(ratingMin: rating)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: selected ? cs.primary : cs.outline,
              ),
              const SizedBox(width: 8),
              if (rating != null) ...[
                Icon(Icons.star_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 2),
                Text('$rating'),
                const SizedBox(width: 4),
                Text('plp.and_up'.tr()),
              ] else
                Text(label),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        tile(null, 'plp.rating_all'.tr()),
        tile(4, ''),
        tile(3, ''),
        tile(2, ''),
      ],
    );
  }

  // ── Free shipping ─────────────────────────────────────────────────────────
  Widget _freeShipping(PlpFilters filters) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('plp.free_shipping'.tr()),
      value: filters.freeShippingOnly,
      onChanged: (v) => _notifier.update((f) => f.copyWith(freeShippingOnly: v)),
    );
  }
}

class _DenseCheckbox extends StatelessWidget {
  const _DenseCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
            ),
          ),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
