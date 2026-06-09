import 'package:flutter/foundation.dart';

/// Sort options for a product listing. `token` is the wire value the catalog
/// API expects (matches `sort_sheet.dart` + `listProducts(sort:)`); these are
/// the app's real tokens (e.g. `bestseller`, `cashback_desc`), not illustrative
/// ones — see REPORT §8.4.
enum PlpSort {
  recommended('recommended'),
  bestseller('bestseller'),
  newest('newest'),
  priceAsc('price_asc'),
  priceDesc('price_desc'),
  cashbackDesc('cashback_desc');

  const PlpSort(this.token);
  final String token;

  /// Resolves a wire token to a [PlpSort], falling back to [recommended] for
  /// unknown/malformed input (never throws).
  static PlpSort fromToken(String? token) {
    for (final s in PlpSort.values) {
      if (s.token == token) return s;
    }
    return PlpSort.recommended;
  }
}

/// Sentinel so [PlpFilters.copyWith] can distinguish "leave unchanged" from
/// "set to null" for the nullable fields.
const Object _unset = Object();

/// Canonical, immutable state of a product listing page (sort + filters +
/// page). Round-trips to/from URL query params via `PlpFiltersCodec`, and is
/// used as a Riverpod family value (so == / hashCode must be correct).
@immutable
class PlpFilters {
  const PlpFilters({
    this.sort = PlpSort.recommended,
    this.priceMinMinor,
    this.priceMaxMinor,
    this.brands = const [],
    this.ratingMin,
    this.freeShippingOnly = false,
    this.inStock = false,
    this.priceDropped = false,
    this.page = 1,
  });

  final PlpSort sort;
  final int? priceMinMinor;
  final int? priceMaxMinor;
  final List<String> brands;
  final int? ratingMin; // 1..5 inclusive when set
  final bool freeShippingOnly;
  final bool inStock;
  final bool priceDropped; // PLP-14: only products whose price dropped in 30d
  final int page;

  PlpFilters copyWith({
    PlpSort? sort,
    Object? priceMinMinor = _unset,
    Object? priceMaxMinor = _unset,
    List<String>? brands,
    Object? ratingMin = _unset,
    bool? freeShippingOnly,
    bool? inStock,
    bool? priceDropped,
    int? page,
  }) {
    return PlpFilters(
      sort: sort ?? this.sort,
      priceMinMinor:
          identical(priceMinMinor, _unset) ? this.priceMinMinor : priceMinMinor as int?,
      priceMaxMinor:
          identical(priceMaxMinor, _unset) ? this.priceMaxMinor : priceMaxMinor as int?,
      brands: brands ?? this.brands,
      ratingMin: identical(ratingMin, _unset) ? this.ratingMin : ratingMin as int?,
      freeShippingOnly: freeShippingOnly ?? this.freeShippingOnly,
      inStock: inStock ?? this.inStock,
      priceDropped: priceDropped ?? this.priceDropped,
      page: page ?? this.page,
    );
  }

  /// True when every field is its default (a fresh, unfiltered listing).
  bool get isEmpty =>
      sort == PlpSort.recommended &&
      priceMinMinor == null &&
      priceMaxMinor == null &&
      brands.isEmpty &&
      ratingMin == null &&
      !freeShippingOnly &&
      !inStock &&
      !priceDropped &&
      page == 1;

  /// Count of active *filters* (not sort, not page) for the sidebar's chip row:
  /// price range counts once, each brand counts, rating once, free-shipping once,
  /// in-stock once, price-dropped once.
  int get activeChipCount {
    var n = 0;
    if (priceMinMinor != null || priceMaxMinor != null) n++;
    n += brands.length;
    if (ratingMin != null) n++;
    if (freeShippingOnly) n++;
    if (inStock) n++;
    if (priceDropped) n++;
    return n;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlpFilters &&
          other.sort == sort &&
          other.priceMinMinor == priceMinMinor &&
          other.priceMaxMinor == priceMaxMinor &&
          listEquals(other.brands, brands) &&
          other.ratingMin == ratingMin &&
          other.freeShippingOnly == freeShippingOnly &&
          other.inStock == inStock &&
          other.priceDropped == priceDropped &&
          other.page == page);

  @override
  int get hashCode => Object.hash(
        sort,
        priceMinMinor,
        priceMaxMinor,
        Object.hashAll(brands),
        ratingMin,
        freeShippingOnly,
        inStock,
        priceDropped,
        page,
      );
}
