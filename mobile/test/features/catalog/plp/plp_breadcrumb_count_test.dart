import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/plp/widgets/plp_breadcrumb.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/filtered_products_provider.dart';
import 'package:mopro/features/catalog/providers/products_by_category_provider.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../../_support/test_harness.dart';

// PLP-04 (result count) + PLP-05 (breadcrumb). `.tr()` returns keys here.

Category _cat(int id, String name, {int? parent}) =>
    Category(id: id, name: name, slug: name.toLowerCase(), commissionPctBps: 1000, parentId: parent);

class _Cats extends CategoriesNotifier {
  @override
  CategoriesState build() => CategoriesState(
        categories: AsyncData([
          _cat(5, 'Elektronik'),
          _cat(8, 'Telefon', parent: 5),
          _cat(9, 'Akilli', parent: 8),
        ]),
      );
}

class _FakeFiltered extends FilteredProductsNotifier {
  @override
  ProductsState build(String arg) =>
      const ProductsState(products: AsyncData([]), total: 42);
}

class _EmptyFiltered extends FilteredProductsNotifier {
  @override
  ProductsState build(String arg) =>
      const ProductsState(products: AsyncData([]));
}

void main() {
  setUpAll(initTestEnv);

  Future<void> pumpCrumb(WidgetTester tester, int categoryId) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => Scaffold(body: PlpBreadcrumb(categoryId: categoryId))),
        GoRoute(path: '/categories/:id', builder: (_, s) => Scaffold(body: Text('CAT ${s.pathParameters['id']}'))),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [categoriesProvider.overrideWith(_Cats.new)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('breadcrumb shows the full ancestry chain', (tester) async {
    await pumpCrumb(tester, 9); // Akilli ← Telefon ← Elektronik
    expect(find.text('plp.breadcrumb_home'), findsOneWidget);
    expect(find.text('Elektronik'), findsOneWidget);
    expect(find.text('Telefon'), findsOneWidget);
    expect(find.text('Akilli'), findsOneWidget);
  });

  testWidgets('tapping an ancestor crumb navigates to it', (tester) async {
    await pumpCrumb(tester, 9);
    await tester.tap(find.text('Telefon'));
    await tester.pumpAndSettle();
    expect(find.text('CAT 8'), findsOneWidget);
  });

  testWidgets('breadcrumb is empty when the tree is unavailable', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: PlpBreadcrumb(categoryId: 9))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Elektronik'), findsNothing);
  });

  testWidgets('result count renders from total', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [filteredProductsProvider.overrideWith(_FakeFiltered.new)],
        child: const MaterialApp(home: Scaffold(body: PlpResultCount(plpKey: '5'))),
      ),
    );
    await tester.pump();
    expect(find.text('plp.result_count'), findsOneWidget);
  });

  testWidgets('result count hidden until total lands', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [filteredProductsProvider.overrideWith(_EmptyFiltered.new)],
        child: const MaterialApp(home: Scaffold(body: PlpResultCount(plpKey: '99'))),
      ),
    );
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });
}
