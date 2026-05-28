/// Integration tests for the guest -> authenticated merge flows.
///
/// These run as widget/provider tests (not flutter integration_test/) — they
/// exercise the full provider graph but stub Dio responses so they run in
/// `flutter test` without a device.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/storage/token_storage.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/cart/application/guest_cart_provider.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

/// In-memory TokenStorage that records save() calls and reads.
class _FakeTokenStorage implements TokenStorage {
  String? _access;
  String? _refresh;
  DateTime? _expiresAt;

  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int accessExpiresIn,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
    _expiresAt = DateTime.now().add(Duration(seconds: accessExpiresIn));
  }

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<DateTime?> readAccessExpiresAt() async => _expiresAt;

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _expiresAt = null;
  }
}

/// Records every request and returns canned JSON for matching paths.
class _RecordingHandler {
  final List<RequestOptions> requests = [];

  Dio build() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final path = options.path;
          // Canned 204 / 200 for the merge endpoints.
          if (path == '/cart/merge') {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'merged':
                      ((options.data as Map?)?['items'] as List?)?.length ?? 0,
                },
              ),
            );
          }
          if (path == '/favorites/sync') {
            return handler.resolve(
              Response(requestOptions: options, statusCode: 204),
            );
          }
          // Default: 404
          return handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 404,
              ),
            ),
          );
        },
      ),
    );
    return dio;
  }

  RequestOptions? lastFor(String path) {
    for (final r in requests.reversed) {
      if (r.path == path) return r;
    }
    return null;
  }
}

Future<ProviderContainer> _makeContainer({
  required _FakeTokenStorage storage,
  required _RecordingHandler handler,
}) async {
  // Reset prefs for each container so tests are isolated.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      tokenStorageProvider.overrideWithValue(storage),
      dioProvider.overrideWithValue(handler.build()),
    ],
  );
}

void main() {
  setUpAll(initTestEnv);

  group('Flow A — guest favorites → login → merged', () {
    test('local favorites are POSTed to /favorites/sync on login', () async {
      final storage = _FakeTokenStorage();
      final handler = _RecordingHandler();
      final container =
          await _makeContainer(storage: storage, handler: handler);
      addTearDown(container.dispose);

      // Guest adds three favorites locally.
      container.read(favoritesProvider.notifier)
        ..toggle(11)
        ..toggle(22)
        ..toggle(33);
      expect(container.read(favoritesProvider), {11, 22, 33});

      // User authenticates.
      await container
          .read(authNotifierProvider.notifier)
          .setAuthenticated(
            accessToken: 'access-x',
            refreshToken: 'refresh-x',
            expiresIn: 900,
          );

      // The merge POST happened with the right body.
      final req = handler.lastFor('/favorites/sync');
      expect(req, isNotNull, reason: 'favorites/sync should be called on auth');
      expect(req!.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect((body['product_ids'] as List).toSet(), {11, 22, 33});

      // Auth state is now Authenticated.
      expect(
        container.read(authNotifierProvider).valueOrNull,
        isA<AuthAuthenticated>(),
      );
    });

    test('no merge call when guest has no favorites', () async {
      final storage = _FakeTokenStorage();
      final handler = _RecordingHandler();
      final container =
          await _makeContainer(storage: storage, handler: handler);
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: 'a',
            refreshToken: 'r',
            expiresIn: 900,
          );

      expect(handler.lastFor('/favorites/sync'), isNull);
    });
  });

  group('Flow B — guest cart → login → merged', () {
    test('local cart items are POSTed to /cart/merge and cleared', () async {
      final storage = _FakeTokenStorage();
      final handler = _RecordingHandler();
      final container =
          await _makeContainer(storage: storage, handler: handler);
      addTearDown(container.dispose);

      // Guest adds items to local cart.
      container.read(guestCartProvider.notifier)
        ..addItem(productId: 1001, variantId: 5001, qty: 2)
        ..addItem(productId: 1002, variantId: 5002);
      expect(container.read(guestCartProvider).length, 2);

      await container.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: 'a',
            refreshToken: 'r',
            expiresIn: 900,
          );

      final req = handler.lastFor('/cart/merge');
      expect(req, isNotNull, reason: 'cart/merge should be called on auth');
      expect(req!.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>;
      expect(items.length, 2);
      expect(
        items.firstWhere((i) => (i as Map)['variant_id'] == 5001),
        {'variant_id': 5001, 'qty': 2},
      );
      expect(
        items.firstWhere((i) => (i as Map)['variant_id'] == 5002),
        {'variant_id': 5002, 'qty': 1},
      );

      // Local cart cleared after successful merge.
      expect(container.read(guestCartProvider), isEmpty);
    });
  });

  group('Flow B addendum — merge failure leaves guest cart intact', () {
    test('local cart NOT cleared if /cart/merge fails', () async {
      final storage = _FakeTokenStorage();
      // Build a Dio that 500s on /cart/merge.
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/cart/merge') {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 500),
            ),);
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 204,
          ),);
        },
      ),);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStorageProvider.overrideWithValue(storage),
        dioProvider.overrideWithValue(dio),
      ],);
      addTearDown(container.dispose);

      container.read(guestCartProvider.notifier).addItem(
            productId: 1, variantId: 99, qty: 3,
          );

      await container.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: 'a', refreshToken: 'r', expiresIn: 900,
          );

      // Cart still has the item — caller will retry on next login attempt.
      expect(container.read(guestCartProvider).length, 1);
      // Auth still completed.
      expect(
        container.read(authNotifierProvider).valueOrNull,
        isA<AuthAuthenticated>(),
      );
    });
  });
}
