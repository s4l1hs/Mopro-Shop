import 'package:mopro/features/catalog/plp/plp_filters.dart';

/// Round-trips [PlpFilters] to/from a URL query-parameter map.
///
/// - [encode] skips defaults so URLs stay short.
/// - [decode] is fully defensive: unknown sort → recommended, non-integer or
///   negative prices dropped, out-of-range rating dropped, empty brands
///   dropped, page < 1 → 1. Malformed input never throws.
///
/// Query keys: `sort`, `min`, `max`, `brand` (comma-joined), `rating`,
/// `shipping` (`free`), `stock` (`in`), `page`.
class PlpFiltersCodec {
  const PlpFiltersCodec();

  Map<String, String> encode(PlpFilters f) {
    final out = <String, String>{};
    if (f.sort != PlpSort.recommended) out['sort'] = f.sort.token;
    if (f.priceMinMinor != null) out['min'] = '${f.priceMinMinor}';
    if (f.priceMaxMinor != null) out['max'] = '${f.priceMaxMinor}';
    if (f.brands.isNotEmpty) out['brand'] = f.brands.join(',');
    if (f.ratingMin != null) out['rating'] = '${f.ratingMin}';
    if (f.freeShippingOnly) out['shipping'] = 'free';
    if (f.inStock) out['stock'] = 'in';
    if (f.page > 1) out['page'] = '${f.page}';
    return out;
  }

  PlpFilters decode(Map<String, String> q) {
    return PlpFilters(
      sort: PlpSort.fromToken(q['sort']),
      priceMinMinor: _positiveInt(q['min']),
      priceMaxMinor: _positiveInt(q['max']),
      brands: _brands(q['brand']),
      ratingMin: _rating(q['rating']),
      freeShippingOnly: q['shipping'] == 'free',
      inStock: q['stock'] == 'in',
      page: _page(q['page']),
    );
  }

  static int? _positiveInt(String? s) {
    if (s == null) return null;
    final v = int.tryParse(s);
    return (v != null && v >= 0) ? v : null;
  }

  static int? _rating(String? s) {
    if (s == null) return null;
    final v = int.tryParse(s);
    return (v != null && v >= 1 && v <= 5) ? v : null;
  }

  static List<String> _brands(String? s) {
    if (s == null || s.isEmpty) return const [];
    final list = s.split(',').where((b) => b.trim().isNotEmpty).toList();
    return list.isEmpty ? const [] : list;
  }

  static int _page(String? s) {
    final v = int.tryParse(s ?? '');
    return (v != null && v >= 1) ? v : 1;
  }
}
