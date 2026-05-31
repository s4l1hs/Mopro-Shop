// ignore_for_file: cascade_invocations — sequential svc/container calls read
// more clearly as separate statements here.
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
import 'package:shared_preferences/shared_preferences.dart';

// ── Flow FF — consent gate + product_view ingest (instrumentation contract) ───
//
// Container-level rather than widget-level: the PDP's post-frame `track()` is a
// thin 3-line call; the value here is proving the analyticsService gate +
// batched flush + ingest payload end-to-end, which a ProviderContainer exercises
// deterministically (no navigator/pumpAndSettle/timer flakiness).

/// Captures POST /analytics/events bodies; 204 for everything else.
class _AnalyticsAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> posts = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path.contains('/analytics/events')) {
      posts.add(options.data as Map<String, dynamic>);
    }
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}

  List<String> eventTypes() => [
        for (final p in posts)
          for (final e in (p['events'] as List<dynamic>))
            (e as Map<String, dynamic>)['type'] as String,
      ];
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

Future<(ProviderContainer, _AnalyticsAdapter)> _container({
  required bool authed,
  required bool consentOn,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _AnalyticsAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(dio),
      authNotifierProvider.overrideWith(
        () => _FakeAuth(authed ? const AuthAuthenticated() : const AuthUnauthenticated()),
      ),
      userConsentProvider.overrideWith(
        () => _StubConsent(UserConsent(authed: authed, analyticsEnabled: consentOn)),
      ),
    ],
  );
  await c.read(authNotifierProvider.future);
  c.read(userConsentProvider);
  return (c, adapter);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('consent ON: product_view reaches ingest with payload', () async {
    final (c, adapter) = await _container(authed: true, consentOn: true);
    final svc = c.read(analyticsServiceProvider);
    svc.track(AnalyticsEvent('product_view', {'productId': 7}));
    await svc.flush();

    expect(adapter.posts, isNotEmpty);
    expect(adapter.eventTypes(), contains('product_view'));
    final pv = [
      for (final p in adapter.posts)
        for (final e in (p['events'] as List<dynamic>))
          if ((e as Map<String, dynamic>)['type'] == 'product_view')
            e['payload'] as Map<String, dynamic>,
    ];
    expect(pv.any((pl) => pl['productId'] == 7), isTrue);
    svc.dispose();
    c.dispose();
  });

  test('consent OFF: events are dropped at the gate', () async {
    final (c, adapter) = await _container(authed: true, consentOn: false);
    final svc = c.read(analyticsServiceProvider);
    svc.track(AnalyticsEvent('product_view', {'productId': 8}));
    await svc.flush();
    expect(adapter.posts, isEmpty);
    svc.dispose();
    c.dispose();
  });

  test('guest: events are dropped (Option A — no guest tracking)', () async {
    final (c, adapter) = await _container(authed: false, consentOn: false);
    final svc = c.read(analyticsServiceProvider);
    svc.track(AnalyticsEvent('product_view', {'productId': 9}));
    await svc.flush();
    expect(adapter.posts, isEmpty);
    svc.dispose();
    c.dispose();
  });
}
