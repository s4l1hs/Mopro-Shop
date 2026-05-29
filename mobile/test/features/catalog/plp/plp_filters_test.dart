import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_codec.dart';

void main() {
  const codec = PlpFiltersCodec();

  group('PlpFilters value object', () {
    test('default is empty', () {
      expect(const PlpFilters().isEmpty, isTrue);
    });

    test('copyWith clears a nullable field with explicit null, else preserves',
        () {
      const f = PlpFilters(priceMinMinor: 100, priceMaxMinor: 500);
      expect(f.copyWith(priceMinMinor: null).priceMinMinor, isNull);
      expect(f.copyWith(priceMinMinor: null).priceMaxMinor, 500); // preserved
      expect(f.copyWith(sort: PlpSort.newest).priceMinMinor, 100); // preserved
    });

    test('activeChipCount counts price-range once, brands each, rating, shipping',
        () {
      expect(const PlpFilters().activeChipCount, 0);
      expect(
        const PlpFilters(
          priceMinMinor: 1,
          brands: ['a', 'b'],
          ratingMin: 4,
          freeShippingOnly: true,
        ).activeChipCount,
        1 + 2 + 1 + 1,
      );
      // sort + page are not "chips".
      expect(const PlpFilters(sort: PlpSort.newest, page: 3).activeChipCount, 0);
    });

    test('equality + hashCode account for brand list', () {
      const a = PlpFilters(brands: ['x', 'y']);
      const b = PlpFilters(brands: ['x', 'y']);
      const c = PlpFilters(brands: ['y', 'x']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('PlpSort.fromToken falls back to recommended on unknown', () {
      expect(PlpSort.fromToken('price_asc'), PlpSort.priceAsc);
      expect(PlpSort.fromToken('💩'), PlpSort.recommended);
      expect(PlpSort.fromToken(null), PlpSort.recommended);
    });
  });

  group('PlpFiltersCodec', () {
    test('empty filters encode to an empty map', () {
      expect(codec.encode(const PlpFilters()), isEmpty);
    });

    test('encode skips defaults', () {
      expect(codec.encode(const PlpFilters(sort: PlpSort.newest)), {'sort': 'newest'});
      expect(codec.encode(const PlpFilters(page: 2)), {'page': '2'});
    });

    test('round-trips all fields', () {
      const f = PlpFilters(
        sort: PlpSort.priceAsc,
        priceMinMinor: 10000,
        priceMaxMinor: 50000,
        brands: ['foo', 'bar'],
        ratingMin: 4,
        freeShippingOnly: true,
        page: 3,
      );
      expect(codec.decode(codec.encode(f)), f);
    });

    test('decodes the §3.8 sample URL params', () {
      final f = codec.decode({
        'sort': 'price_asc',
        'min': '10000',
        'max': '50000',
        'brand': 'foo,bar',
        'rating': '4',
        'shipping': 'free',
      });
      expect(f.sort, PlpSort.priceAsc);
      expect(f.priceMinMinor, 10000);
      expect(f.priceMaxMinor, 50000);
      expect(f.brands, ['foo', 'bar']);
      expect(f.ratingMin, 4);
      expect(f.freeShippingOnly, isTrue);
    });

    test('defensive decode: malformed input falls back, never throws', () {
      expect(codec.decode({'sort': '💩'}).sort, PlpSort.recommended);
      expect(codec.decode({'min': 'abc'}).priceMinMinor, isNull);
      expect(codec.decode({'min': '-5'}).priceMinMinor, isNull);
      expect(codec.decode({'rating': '9'}).ratingMin, isNull);
      expect(codec.decode({'rating': '0'}).ratingMin, isNull);
      expect(codec.decode({'brand': ',, ,'}).brands, isEmpty);
      expect(codec.decode({'page': '0'}).page, 1);
      expect(codec.decode({'page': 'x'}).page, 1);
      expect(
        () => codec.decode({
          'min': '💩',
          'max': '',
          'brand': ',,',
          'rating': 'x',
          'page': '-1',
          'sort': '??',
        }),
        returnsNormally,
      );
    });

    test('ignores unknown params', () {
      expect(codec.decode({'wat': '1', 'sort': 'newest'}).sort, PlpSort.newest);
    });
  });
}
