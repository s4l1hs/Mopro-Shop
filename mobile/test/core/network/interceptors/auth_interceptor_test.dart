import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/network/interceptors/auth_interceptor.dart';
import 'package:mopro/core/storage/token_storage.dart';

import 'auth_interceptor_test.mocks.dart';

class _TestReqHandler extends RequestInterceptorHandler {
  @override
  void next(RequestOptions options) {}
  @override
  void reject(
    DioException error, [
    bool callFollowingErrorInterceptor = false,
  ]) {}
  @override
  void resolve(
    Response<dynamic> response, [
    bool callFollowingResponseInterceptor = false,
  ]) {}
}

// Dio 5.9.2 ErrorInterceptorHandler: reject/resolve have no optional bool param.
class _TestErrHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  bool rejectCalled = false;
  bool resolveCalled = false;
  DioException? rejectedError;

  @override
  void next(DioException err) {
    nextCalled = true;
  }

  @override
  void reject(DioException err) {
    rejectCalled = true;
    rejectedError = err;
  }

  @override
  void resolve(Response<dynamic> response) {
    resolveCalled = true;
  }
}

@GenerateMocks([TokenStorage, Dio])
void main() {
  late MockTokenStorage mockStorage;
  late MockDio mockRefreshDio;
  late AuthInterceptor interceptor;
  var logoutCallCount = 0;

  setUp(() {
    mockStorage = MockTokenStorage();
    mockRefreshDio = MockDio();
    logoutCallCount = 0;

    interceptor = AuthInterceptor(
      tokenStorage: mockStorage,
      refreshDio: mockRefreshDio,
      onLogout: () async => logoutCallCount++,
    );
  });

  group('AuthInterceptor', () {
    test('injects Bearer token on request when token is present', () async {
      when(mockStorage.readAccessToken()).thenAnswer((_) async => 'tok123');
      final options = RequestOptions(path: '/v1/test', method: 'GET');
      await interceptor.onRequest(options, _TestReqHandler());
      expect(options.headers['Authorization'], equals('Bearer tok123'));
    });

    test('does not inject Authorization when no token stored', () async {
      when(mockStorage.readAccessToken()).thenAnswer((_) async => null);
      final options = RequestOptions(path: '/v1/test', method: 'GET');
      await interceptor.onRequest(options, _TestReqHandler());
      expect(options.headers.containsKey('Authorization'), isFalse);
    });

    // Critical test: 3 concurrent 401s → refreshDio.post called EXACTLY ONCE.
    test('concurrent 401s collapse into a single refresh call', () async {
      when(mockStorage.readRefreshToken())
          .thenAnswer((_) async => 'refresh-tok');
      when(mockStorage.readAccessToken())
          .thenAnswer((_) async => 'new-access-tok');
      when(
        mockStorage.save(
          accessToken: anyNamed('accessToken'),
          refreshToken: anyNamed('refreshToken'),
          accessExpiresIn: anyNamed('accessExpiresIn'),
        ),
      ).thenAnswer((_) async {});

      final refreshCompleter = Completer<Response<Map<String, dynamic>>>();
      when(
        mockRefreshDio.post<Map<String, dynamic>>(
          '/v1/auth/token/refresh',
          data: anyNamed('data'),
        ),
      ).thenAnswer((_) => refreshCompleter.future);

      when(mockRefreshDio.fetch<dynamic>(any)).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: RequestOptions(path: '/v1/any'),
        ),
      );

      final err401 = DioException(
        requestOptions: RequestOptions(path: '/v1/any'),
        response: Response<dynamic>(
          statusCode: 401,
          requestOptions: RequestOptions(path: '/v1/any'),
        ),
        type: DioExceptionType.badResponse,
      );

      // 3 concurrent 401 errors.
      final futures = [
        interceptor.onError(err401, _TestErrHandler()),
        interceptor.onError(err401, _TestErrHandler()),
        interceptor.onError(err401, _TestErrHandler()),
      ];

      await Future<void>.delayed(Duration.zero);

      refreshCompleter.complete(
        Response<Map<String, dynamic>>(
          statusCode: 200,
          data: {
            'access_token': 'new-access-tok',
            'refresh_token': 'new-refresh-tok',
            'expires_in': 900,
          },
          requestOptions: RequestOptions(path: '/v1/auth/token/refresh'),
        ),
      );

      await Future.wait(futures);

      // refreshDio.post must have been called EXACTLY ONCE.
      verify(
        mockRefreshDio.post<Map<String, dynamic>>(
          '/v1/auth/token/refresh',
          data: anyNamed('data'),
        ),
      ).called(1);
    });

    test('calls onLogout and rejects when refresh token missing', () async {
      when(mockStorage.readRefreshToken()).thenAnswer((_) async => null);

      final err401 = DioException(
        requestOptions: RequestOptions(path: '/v1/any'),
        response: Response<dynamic>(
          statusCode: 401,
          requestOptions: RequestOptions(path: '/v1/any'),
        ),
        type: DioExceptionType.badResponse,
      );

      final handler = _TestErrHandler();
      await interceptor.onError(err401, handler);

      expect(logoutCallCount, equals(1));
      expect(handler.rejectCalled, isTrue);
      expect(handler.rejectedError?.error, isA<UnauthorizedError>());
    });

    test('passes through non-401 errors unchanged', () async {
      final err500 = DioException(
        requestOptions: RequestOptions(path: '/v1/any'),
        response: Response<dynamic>(
          statusCode: 500,
          requestOptions: RequestOptions(path: '/v1/any'),
        ),
        type: DioExceptionType.badResponse,
      );

      final handler = _TestErrHandler();
      await interceptor.onError(err500, handler);

      verifyNever(mockStorage.readRefreshToken());
      expect(handler.nextCalled, isTrue);
    });
  });
}
