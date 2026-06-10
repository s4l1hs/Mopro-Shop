import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Shared PLP filter facets, wired to `plpFiltersProvider(plpKey)`. Extracted
/// from the desktop `FilterPanel` so the mobile filter sheet (PLP-01) renders
/// the exact same Brand + Rating controls — one source of truth for both.

/// Searchable brand list: a search field + dense checkboxes, capped at 8 with a
/// "show more" until searched. Brands are the distinct brands of the current
/// result set (no aggregation endpoint yet — REPORT backlog).
class PlpBrandFacet extends ConsumerStatefulWidget {
  const PlpBrandFacet({required this.plpKey, required this.brands, super.key});

  final String plpKey;
  final List<String> brands;

  @override
  ConsumerState<PlpBrandFacet> createState() => _PlpBrandFacetState();
}

class _PlpBrandFacetState extends ConsumerState<PlpBrandFacet> {
  final _brandQuery = TextEditingController();
  bool _showAllBrands = false;

  @override
  void dispose() {
    _brandQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(plpFiltersProvider(widget.plpKey));
    final notifier = ref.read(plpFiltersProvider(widget.plpKey).notifier);
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
              notifier.update((f) => f.copyWith(brands: next, page: 1));
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
}

/// Rating buckets: All / 4+ / 3+ / 2+ (radio-style). Active uses the brand token.
class PlpRatingFacet extends ConsumerWidget {
  const PlpRatingFacet({required this.plpKey, super.key});

  final String plpKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(plpFiltersProvider(plpKey));
    final notifier = ref.read(plpFiltersProvider(plpKey).notifier);
    final cs = Theme.of(context).colorScheme;

    // Custom radio (Icon) to avoid the deprecated Radio.groupValue/onChanged
    // API — the project-wide Radio→RadioGroup migration is a separate backlog.
    Widget tile(int? rating, String label) {
      final selected = filters.ratingMin == rating;
      return InkWell(
        onTap: () => notifier.update((f) => f.copyWith(ratingMin: rating)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
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
}

/// PLP-13: one attribute facet (e.g. `renk`) as dense checkboxes with each
/// value's product count, bound to `plpFiltersProvider(plpKey).attrs[facet.slug]`.
/// Mirrors [PlpBrandFacet]; values + counts come from the #160 facets endpoint
/// (the facet's `name` is already server-localized, so no client i18n).
class PlpAttributeFacet extends ConsumerWidget {
  const PlpAttributeFacet({required this.plpKey, required this.facet, super.key});

  final String plpKey;
  final Facet facet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(plpFiltersProvider(plpKey));
    final notifier = ref.read(plpFiltersProvider(plpKey).notifier);
    final selected = filters.attrs[facet.slug] ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final fv in facet.values)
          _DenseCheckbox(
            label: '${fv.value} (${fv.count})',
            value: selected.contains(fv.value),
            onChanged: (_) => notifier.toggleAttr(facet.slug, fv.value),
          ),
      ],
    );
  }
}

/// Dense checkbox row (shared by the brand facet).
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
