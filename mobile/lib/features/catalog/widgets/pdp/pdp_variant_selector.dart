import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro_api/mopro_api.dart';

/// Variant chips for the PDP buy-box. The catalog API returns a flat
/// `List<Variant>` (each carrying optional color/size), not attribute groups,
/// so this renders one [FilterChip] per variant with a "color / size" label
/// (falling back to the SKU). Extracted from the PDP buy-box so mobile and
/// desktop share one selector. Renders nothing for a single-variant product.
/// Out-of-stock variants (`stock == 0`) render struck-through + disabled (P-015).
class PdpVariantSelector extends StatelessWidget {
  const PdpVariantSelector({
    required this.variants,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<Variant> variants;
  final Variant? selected;
  final ValueChanged<Variant> onChanged;

  static String variantLabel(Variant v) {
    final parts = <String>[];
    if (v.color != null && v.color!.isNotEmpty) parts.add(v.color!);
    if (v.size != null && v.size!.isNotEmpty) parts.add(v.size!);
    return parts.isEmpty ? v.sku : parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    if (variants.length <= 1) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('product.select_variant'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: variants.map((v) {
            final inStock = v.stock > 0;
            return FilterChip(
              label: Text(
                variantLabel(v),
                style: inStock
                    ? null
                    : const TextStyle(decoration: TextDecoration.lineThrough),
              ),
              selected: selected?.id == v.id,
              // Out-of-stock variants render struck-through + disabled so they
              // can't be selected into the buy box (P-015 parity treatment).
              onSelected: inStock ? (_) => onChanged(v) : null,
            );
          }).toList(),
        ),
      ],
    );
  }
}
