// ignore_for_file: cascade_invocations
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/catalog/data/similar_products_provider.dart';
import 'package:mopro/features/home/home_recommendations_provider.dart';

// ── Flow SS/TT/UU — recommendation surfaces (feat/recommendation-surfaces) ────
// Container/widget level (deterministic; mirrors the Flow CC/DD/EE analytics
// trio). The backend ranking is covered by the Go analytics integration tests;
// here we validate the client wiring: source-tagged home recs, the PDP similar
// rail, and the defensive errors→empty layering.

class _Adapter implements HttpClientAdapter {
  String homeSource = 'popular';
  int homeCount = 3;
  int similarCount = 4;
  bool failHome = false;
  bool failSimilar = false;

  ResponseBody _json(Object body) => ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  List<Map<String, dynamic>> _products(int n, int base) => [
        for (var i = 0; i < n; i++)
          {
            'id': base + i,
            'seller_id': 1,
            'category_id': 42,
            'brand': 'Acme',
            'status': 'active',
            'title': 'Ürün ${base + i}',
            'price_minor': 12900,
            'price_currency': 'TRY',
            'cashback_preview': {'monthly_amount_minor': 100, 'currency': 'TRY_COIN'},
          },
      ];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final p = o.path;
    if (p.contains('/recommendations/home')) {
      if (failHome) throw DioException(requestOptions: o, error: 'boom');
      return _json({'data': _products(homeCount, 200), 'source': homeSource});
    }
    if (p.contains('/similar')) {
      if (failSimilar) throw DioException(requestOptions: o, error: 'boom');
      return _json({'data': _products(similarCount, 300), 'source': 'co_view'});
    }
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._s);
  final AuthState _s;
  @override
  Future<AuthState> build() async => _s;
}

Future<ProviderContainer> _container(_Adapter adapter, AuthState auth) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local'))..httpClientAdapter = adapter;
  final c = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    authNotifierProvider.overrideWith(() => _FakeAuth(auth)),
  ],);
  await c.read(authNotifierProvider.future);
  return c;
}

/// Polls until the home-recs provider leaves loading (the fake fetch resolved).
Future<void> _settleHome(ProviderContainer c) async {
  for (var i = 0; i < 600 && c.read(homeRecommendationsProvider).isLoading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Flow SS: home rail reflects the server `source` — popular for a guest,
  // personalized when the backend serves co-view recs.
  test('Flow SS: home recommendations carry the source variant', () async {
    final cPop = await _container(_Adapter(), const AuthUnauthenticated());
    cPop.listen(homeRecommendationsProvider, (_, __) {}, fireImmediately: true);
    await _settleHome(cPop);
    final pop = cPop.read(homeRecommendationsProvider).valueOrNull!;
    expect(pop.products.length, 3);
    expect(pop.personalized, isFalse, reason: 'source=popular → not personalized');
    cPop.dispose();

    final cPers = await _container(
      _Adapter()..homeSource = 'personalized',
      const AuthAuthenticated(),
    );
    cPers.listen(homeRecommendationsProvider, (_, __) {}, fireImmediately: true);
    await _settleHome(cPers);
    final pers = cPers.read(homeRecommendationsProvider).valueOrNull!;
    expect(pers.personalized, isTrue, reason: 'source=personalized → personalized');
    expect(pers.products.first.title, 'Ürün 200');
    cPers.dispose();
  });

  // Flow TT: the PDP "Benzer ürünler" rail loads co-view recs for a product id.
  test('Flow TT: similarProductsProvider populates from /products/{id}/similar',
      () async {
    final c = await _container(_Adapter(), const AuthUnauthenticated());
    final products = await c.read(similarProductsProvider(42).future);
    expect(products.length, 4);
    expect(products.first.id, 300);
    c.dispose();
  });

  // Flow UU: defensive layering — a fetch failure resolves to empty data (never
  // an error state), so neither the home rail nor the PDP rail breaks its screen.
  test('Flow UU: fetch errors degrade to empty, not an error state', () async {
    final c = await _container(
      _Adapter()
        ..failHome = true
        ..failSimilar = true,
      const AuthUnauthenticated(),
    );
    c.listen(homeRecommendationsProvider, (_, __) {}, fireImmediately: true);
    await _settleHome(c);

    final home = c.read(homeRecommendationsProvider);
    expect(home.hasError, isFalse, reason: 'home recs must not surface an error');
    expect(home.valueOrNull?.products, isEmpty);

    final similar = await c.read(similarProductsProvider(7).future);
    expect(similar, isEmpty, reason: 'similar must degrade to empty on error');
    c.dispose();
  });
}
