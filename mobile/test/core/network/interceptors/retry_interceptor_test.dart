import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:mopro/core/network/interceptors/retry_interceptor.dart';

import 'retry_interceptor_test.mocks.dart';

// Custom handler: captures outcome without triggering Dio chain machinery.
class _TestErrHandler extends ErrorInterceptorHandler {
  bool nextCalled = false;
  bool resolveCalled = false;

  @override
  void next(DioException err) {
    nextCalled = true;
  }

  @override
  void reject(DioException error) {}

  @override
  void resolve(Response<dynamic> response) {
    resolveCalled = true;
  }
}

@GenerateMocks([Dio])
void main() {
  late MockDio mockDio;
  late RetryInterceptor interceptor;

  setUp(() {
    mockDio = MockDio();
    interceptor = RetryInterceptor(dio: mockDio);
  });

  group('RetryInterceptor', () {
    // Critical test: TestRetryInterceptor_PostWithoutKey_NoRetry
    test('POST 5xx without X-Idempotency-Key is NOT retried', () async {
      final options = RequestOptions(path: '/v1/orders', method: 'POST');
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          statusCode: 503,
          requestOptions: options,
        ),
        type: DioExceptionType.badResponse,
      );
      final handler = _TestErrHandler();
      await interceptor.onError(err, handler);
      verifyNever(mockDio.fetch<dynamic>(any));
      expect(handler.nextCalled, isTrue);
    });

    // Critical test: TestRetryInterceptor_PostWithKey_Retries
    test('POST 5xx WITH X-Idempotency-Key IS retried', () async {
      final options = RequestOptions(
        path: '/v1/orders',
        method: 'POST',
        headers: {'X-Idempotency-Key': 'idem-key-123'},
      );
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          statusCode: 503,
          requestOptions: options,
        ),
        type: DioExceptionType.badResponse,
      );

      when(mockDio.fetch<dynamic>(any)).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: options,
        ),
      );

      final handler = _TestErrHandler();
      await interceptor.onError(err, handler);

      verify(mockDio.fetch<dynamic>(any)).called(1);
      expect(handler.resolveCalled, isTrue);
    });

    test('GET 5xx is retried without idempotency key', () async {
      final options = RequestOptions(path: '/v1/products', method: 'GET');
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          statusCode: 500,
          requestOptions: options,
        ),
        type: DioExceptionType.badResponse,
      );

      when(mockDio.fetch<dynamic>(any)).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: options,
        ),
      );

      final handler = _TestErrHandler();
      await interceptor.onError(err, handler);

      verify(mockDio.fetch<dynamic>(any)).called(1);
      expect(handler.resolveCalled, isTrue);
    });

    test('stops retrying after max attempts', () async {
      final options = RequestOptions(
        path: '/v1/products',
        method: 'GET',
        extra: {'_retryAttempt': 2},
      );
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          statusCode: 500,
          requestOptions: options,
        ),
        type: DioExceptionType.badResponse,
      );

      final handler = _TestErrHandler();
      await interceptor.onError(err, handler);

      verifyNever(mockDio.fetch<dynamic>(any));
      expect(handler.nextCalled, isTrue);
    });

    test('does not retry 4xx errors', () async {
      final options = RequestOptions(path: '/v1/test', method: 'GET');
      final err = DioException(
        requestOptions: options,
        response: Response<dynamic>(
          statusCode: 400,
          requestOptions: options,
        ),
        type: DioExceptionType.badResponse,
      );

      final handler = _TestErrHandler();
      await interceptor.onError(err, handler);

      verifyNever(mockDio.fetch<dynamic>(any));
      expect(handler.nextCalled, isTrue);
    });
  });
}
