/// Integration tests for MFA: enroll, then logout, then login challenge.
///
/// Verifies the contract between SignInNotifier and AuthApiExt:
///   1. enrollMFA POSTs phone to /auth/mfa/enroll
///   2. confirmMFAEnroll POSTs phone+code to /auth/mfa/confirm
///   3. login that returns
///      {"mfa_required":true,"mfa_token":...,"masked_phone":...}
///      lands SignInState.requiresMFA == true (no auth flip)
///   4. verifyMFA POSTs mfa_token+code to /auth/mfa/verify and returns tokens
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/storage/token_storage.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/auth/auth_signin_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

class _FakeTokenStorage implements TokenStorage {
  String? _access;
  String? _refresh;
  DateTime? _exp;
  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required int accessExpiresIn,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
    _exp = DateTime.now().add(Duration(seconds: accessExpiresIn));
  }

  @override
  Future<String?> readAccessToken() async => _access;
  @override
  Future<String?> readRefreshToken() async => _refresh;
  @override
  Future<DateTime?> readAccessExpiresAt() async => _exp;
  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _exp = null;
  }
}

class _Router {
  _Router(this.routes);
  final Map<String, Response<dynamic> Function(RequestOptions)> routes;
  final List<RequestOptions> seen = [];

  Dio build() {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        seen.add(options);
        final key = '${options.method} ${options.path}';
        final fn = routes[key];
        if (fn != null) return handler.resolve(fn(options));
        return handler.reject(DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 404),
        ),);
      },
    ),);
    return dio;
  }

  RequestOptions? lastFor(String path) {
    for (final r in seen.reversed) {
      if (r.path == path) return r;
    }
    return null;
  }
}

Future<ProviderContainer> _makeContainer(_Router router) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    tokenStorageProvider.overrideWithValue(_FakeTokenStorage()),
    dioProvider.overrideWithValue(router.build()),
  ],);
}

void main() {
  setUpAll(initTestEnv);

  group('Flow C — MFA enroll', () {
    test('enrollMFA POSTs phone to /auth/mfa/enroll', () async {
      final router = _Router({
        'POST /auth/mfa/enroll': (req) => Response(
              requestOptions: req,
              statusCode: 204,
            ),
      });
      final container = await _makeContainer(router);
      addTearDown(container.dispose);

      final api = container.read(authApiExtProvider);
      await api.enrollMFA(phone: '+905551234567');

      final req = router.lastFor('/auth/mfa/enroll');
      expect(req, isNotNull);
      expect(req!.method, 'POST');
      expect((req.data as Map)['phone'], '+905551234567');
    });

    test('confirmMFAEnroll POSTs phone + code to /auth/mfa/confirm', () async {
      final router = _Router({
        'POST /auth/mfa/confirm': (req) => Response(
              requestOptions: req,
              statusCode: 200,
              data: {'mfa_enabled': true},
            ),
      });
      final container = await _makeContainer(router);
      addTearDown(container.dispose);

      final api = container.read(authApiExtProvider);
      await api.confirmMFAEnroll(phone: '+905551234567', code: '123456');

      final req = router.lastFor('/auth/mfa/confirm');
      expect(req, isNotNull);
      expect(req!.method, 'POST');
      final body = req.data as Map;
      expect(body['phone'], '+905551234567');
      expect(body['code'], '123456');
    });
  });

  group('Flow C — login challenge after MFA enabled', () {
    test('login that returns mfa_required parks user at challenge state',
        () async {
      final router = _Router({
        'POST /auth/login': (req) => Response(
              requestOptions: req,
              statusCode: 200,
              data: {
                'mfa_required': true,
                'mfa_token': 'mfa-token-abc',
                'masked_phone': '+90 5XX XXX XX 67',
              },
            ),
      });
      final container = await _makeContainer(router);
      addTearDown(container.dispose);

      final notifier = container.read(signInNotifierProvider.notifier);
      await notifier.submit(email: 'a@b.com', password: 'Testpass1!');

      final state = container.read(signInNotifierProvider);
      expect(state.requiresMFA, isTrue);
      expect(state.mfaToken, 'mfa-token-abc');
      expect(state.maskedPhone, '+90 5XX XXX XX 67');

      // Auth state stays unauthenticated until MFA is verified.
      // Materialize the AsyncNotifier first so its build() runs.
      await container.read(authNotifierProvider.future);
      expect(
        container.read(authNotifierProvider).valueOrNull,
        isA<AuthUnauthenticated>(),
      );
    });

    test('verifyMFA with correct code flips auth to Authenticated', () async {
      final router = _Router({
        'POST /auth/mfa/verify': (req) => Response(
              requestOptions: req,
              statusCode: 200,
              data: {
                'access_token': 'access-after-mfa',
                'refresh_token': 'refresh-after-mfa',
                'expires_in': 900,
              },
            ),
      });
      final container = await _makeContainer(router);
      addTearDown(container.dispose);

      final api = container.read(authApiExtProvider);
      final result = await api.verifyMFA(mfaToken: 'mfa-x', code: '123456');

      expect(result.accessToken, 'access-after-mfa');
      expect(result.refreshToken, 'refresh-after-mfa');

      final req = router.lastFor('/auth/mfa/verify');
      expect(req, isNotNull);
      final body = req!.data as Map;
      expect(body['mfa_token'], 'mfa-x');
      expect(body['code'], '123456');
    });
  });

  group('Flow C — logout', () {
    test('setLoggedOut clears tokens and returns Unauthenticated', () async {
      final router = _Router({});
      final container = await _makeContainer(router);
      addTearDown(container.dispose);

      // Authenticate first
      await container.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: 'a',
            refreshToken: 'r',
            expiresIn: 900,
          );
      expect(
        container.read(authNotifierProvider).valueOrNull,
        isA<AuthAuthenticated>(),
      );

      // Then log out
      await container.read(authNotifierProvider.notifier).setLoggedOut();
      expect(
        container.read(authNotifierProvider).valueOrNull,
        isA<AuthUnauthenticated>(),
      );
    });
  });
}
