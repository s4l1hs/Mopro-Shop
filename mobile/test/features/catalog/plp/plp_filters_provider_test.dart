import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';

void main() {
  test('default state is empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(plpFiltersProvider('42')).isEmpty, isTrue);
  });

  test('set replaces whole state', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(plpFiltersProvider('42').notifier).set(
          const PlpFilters(sort: PlpSort.newest, priceMinMinor: 100),
        );
    final f = c.read(plpFiltersProvider('42'));
    expect(f.sort, PlpSort.newest);
    expect(f.priceMinMinor, 100);
  });

  test('setSort changes sort and resets page to 1', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(plpFiltersProvider('42').notifier).set(
          const PlpFilters(page: 5),
        );
    c.read(plpFiltersProvider('42').notifier).setSort(PlpSort.priceDesc);
    final f = c.read(plpFiltersProvider('42'));
    expect(f.sort, PlpSort.priceDesc);
    expect(f.page, 1);
  });

  test('families are independent by key', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(plpFiltersProvider('42').notifier).setSort(PlpSort.newest);
    expect(c.read(plpFiltersProvider('99')).sort, PlpSort.recommended);
    // Search sentinel key is its own family instance too.
    expect(c.read(plpFiltersProvider(plpKeyForSearch('shoes'))).isEmpty, isTrue);
  });

  test('key helpers', () {
    expect(plpKeyForCategory(42), '42');
    expect(plpKeyForSearch('shoes'), '_search:shoes');
  });
}
