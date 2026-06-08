// ignore_for_file: cascade_invocations
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/analytics/analytics_service.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Flow CC/DD/EE — the closing trio for the analytics loop (Tranche 4c) ──────
// Container/widget level (deterministic; avoids the navigator/timer flakiness
// that timed out the 4b widget flow). The real backend backfill is covered by
// 4a's Go integration tests; here we validate the client wiring closes the loop.

class _Adapter implements HttpClientAdapter {
  int recentCount = 2;
  int identifyCalls = 0;
  int deleteCalls = 0;

  ResponseBody _json(Object body) => ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final p = o.path;
    if (o.method == 'POST' && p.contains('/analytics/sessions/identify')) {
      identifyCalls++;
      return ResponseBody.fromString('', 204);
    }
    if (o.method == 'DELETE' && p.contains('/me/analytics-data')) {
      deleteCalls++;
      recentCount = 0; // server erased the projection
      return ResponseBody.fromString('', 204);
    }
    if (p.contains('/me/recently-viewed')) {
      return _json({
        'data': [
          for (var i = 0; i < recentCount; i++)
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
        ],
      });
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

class _StubConsent extends UserConsentNotifier {
  _StubConsent(this._s);
  final UserConsent _s;
  @override
  UserConsent build() => _s;
}

Future<(ProviderContainer, _Adapter, ProviderSubscription)> _eligibleContainer() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _Adapter();
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local'))..httpClientAdapter = adapter;
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    dioProvider.overrideWithValue(dio),
    authNotifierProvider.overrideWith(() => _FakeAuth(const AuthAuthenticated())),
    userConsentProvider.overrideWith(
      () => _StubConsent(const UserConsent(authed: true, analyticsEnabled: true)),
    ),
  ],);
  final sub = c.listen(recentlyViewedProvider, (_, __) {}, fireImmediately: true);
  await c.read(authNotifierProvider.future);
  // Rebuild now that auth is authed, then wait deterministically for the fetch
  // to land (a fixed delay is racy on slow CI runners).
  c.invalidate(recentlyViewedProvider);
  await _settle(c);
  return (c, adapter, sub);
}

/// Polls until the provider leaves the loading state (the fake fetch resolved),
/// independent of wall-clock — deterministic on any runner.
Future<void> _settle(ProviderContainer c) async {
  for (var i = 0; i < 600 && c.read(recentlyViewedProvider).isLoading; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Flow CC: eligible user → recentlyViewedProvider yields the server projection
  // (the rail then renders one ProductCard per product — see
  // product_list_rail_test.dart). Container-level to stay deterministic.
  test('Flow CC: eligible → recently-viewed populated from server projection',
      () async {
    final (c, adapter, sub) = await _eligibleContainer();
    final products = c.read(recentlyViewedProvider).valueOrNull ?? const [];
    expect(products.length, 2);
    expect(products.first.title, 'Ürün 0');
    sub.close();
    c.dispose();
  });

  test('Flow DD: identify links the session on login', () async {
    final (c, adapter, sub) = await _eligibleContainer();
    await c.read(analyticsServiceProvider).identify();
    expect(adapter.identifyCalls, 1);
    c.read(analyticsServiceProvider).dispose();
    sub.close();
    c.dispose();
  });

  test('Flow EE: RTBF erase → DELETE fires → rail invalidates to empty', () async {
    final (c, adapter, sub) = await _eligibleContainer();
    expect((c.read(recentlyViewedProvider).valueOrNull ?? const []).length, 2);

    // Mirror the settings handler: deleteAllData() then invalidate the rail.
    final ok = await c.read(userConsentProvider.notifier).deleteAllData();
    expect(ok, isTrue);
    expect(adapter.deleteCalls, 1);
    c.invalidate(recentlyViewedProvider);
    await _settle(c);
    expect(c.read(recentlyViewedProvider).valueOrNull, isEmpty);
    sub.close();
    c.dispose();
  });
}
