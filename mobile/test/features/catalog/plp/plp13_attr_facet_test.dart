import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/plp/attribute_facets_provider.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_codec.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/plp/widgets/filter_panel.dart';
import 'package:mopro_api/mopro_api.dart';

// PLP-13 PR 4 — renk facet: codec round-trip, toggle, and the FilterPanel section.

void main() {
  const codec = PlpFiltersCodec();

  group('PlpFilters.attrs', () {
    test('codec round-trips attrs', () {
      const f = PlpFilters(
        attrs: {
          'renk': ['Siyah', 'Beyaz'],
        },
      );
      final encoded = codec.encode(f);
      expect(encoded['attr_renk'], 'Siyah,Beyaz');
      final decoded = codec.decode(encoded);
      expect(decoded.attrs['renk'], ['Siyah', 'Beyaz']);
      expect(decoded, f); // deep equality
    });

    test('decode is defensive (empty/garbage dropped)', () {
      expect(codec.decode({'attr_': 'x'}).attrs, isEmpty);
      expect(codec.decode({'attr_renk': ' , '}).attrs, isEmpty);
    });

    test('chip count + isEmpty reflect attrs', () {
      const f = PlpFilters(
        attrs: {
          'renk': ['Siyah', 'Beyaz'],
        },
      );
      expect(f.activeChipCount, 2);
      expect(f.isEmpty, isFalse);
      expect(const PlpFilters().isEmpty, isTrue);
    });
  });

  testWidgets('FilterPanel renders the renk facet; checking a value filters',
      (tester) async {
    final facet = Facet(
      slug: 'renk',
      name: 'Renk',
      values: [
        FacetValue(value: 'Siyah', count: 5),
        FacetValue(value: 'Beyaz', count: 3),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        attributeFacetsProvider.overrideWith((ref, id) async => [facet]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: FilterPanel(
                plpKey: '42',
                currentCategoryId: 42,
                showCategoryTree: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The facet section title (server-localized name) + the value+count labels.
    expect(find.text('Renk'), findsOneWidget);
    expect(find.text('Siyah (5)'), findsOneWidget);
    expect(find.text('Beyaz (3)'), findsOneWidget);

    // Toggle 'Siyah' → plpFiltersProvider('42').attrs['renk'] == ['Siyah'].
    await tester.tap(find.text('Siyah (5)'));
    await tester.pumpAndSettle();
    final attrs = container.read(plpFiltersProvider('42')).attrs;
    expect(attrs['renk'], ['Siyah']);
  });
}
