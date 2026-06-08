// ignore_for_file: cascade_invocations
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter({this.count = 2, this.fail = false});
  int count;
  bool fail;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (fail) return ResponseBody.fromString('err', 500);
    final items = [
      for (var i = 0; i < count; i++)
        {
          'id': 100 + i,
          'seller_id': 1,
          'category_id': 42,
          'brand': 'Acme',
          'status': 'active',
          'title': 'Ürün $i',
          'price_minor': 12900,
          'price_currency': 'TRY',
          'cashback_preview': {'monthly_coin_minor': 100, 'currency': 'TRY_COIN'},
        },
    ];
    return ResponseBody.fromString(
      jsonEncode({'data': items}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
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

class _StubConsent extends UserConsentNotifier {
  _StubConsent(this._s);
  final UserConsent _s;
  @override
  UserConsent build() => _s;
}

ProviderContainer _c({
  required bool authed,
  required bool consentOn,
  _Adapter? adapter,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local'))
    ..httpClientAdapter = adapter ?? _Adapter();
  return ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(dio),
      authNotifierProvider.overrideWith(
        () => _FakeAuth(authed ? const AuthAuthenticated() : const AuthUnauthenticated()),
      ),
      userConsentProvider.overrideWith(
        () => _StubConsent(UserConsent(authed: authed, analyticsEnabled: consentOn)),
      ),
    ],
  );
}

Future<List<dynamic>> _resolve(ProviderContainer c) async {
  // Keep the provider alive so it rebuilds when the async auth dependency
  // resolves (a bare read() establishes no subscription).
  final sub = c.listen(recentlyViewedProvider, (_, __) {}, fireImmediately: true);
  await c.read(authNotifierProvider.future);
  c.invalidate(recentlyViewedProvider);
  // Deterministic wait for the (eligible) fetch to settle; ineligible paths
  // never enter loading, so the loop is a no-op for them.
  for (var i = 0; i < 600 && c.read(recentlyViewedProvider).isLoading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  final v = c.read(recentlyViewedProvider).valueOrNull ?? const [];
  sub.close();
  return v;
}

void main() {
  test('guest → empty', () async {
    final c = _c(authed: false, consentOn: false);
    expect(await _resolve(c), isEmpty);
    c.dispose();
  });

  test('consent off → empty', () async {
    final c = _c(authed: true, consentOn: false);
    expect(await _resolve(c), isEmpty);
    c.dispose();
  });

  test('eligible → fetches data', () async {
    final c = _c(authed: true, consentOn: true, adapter: _Adapter(count: 3));
    final products = await _resolve(c);
    expect(products.length, 3);
    c.dispose();
  });

  test('fetch error → empty (defensive layering, not error state)', () async {
    final c = _c(authed: true, consentOn: true, adapter: _Adapter(fail: true));
    final products = await _resolve(c);
    final state = c.read(recentlyViewedProvider);
    expect(state.hasError, isFalse);
    expect(products, isEmpty);
    c.dispose();
  });
}
