import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/network/interceptors/idempotency_interceptor.dart';
import 'package:uuid/uuid.dart';

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

void main() {
  late IdempotencyInterceptor interceptor;

  setUp(() {
    interceptor = IdempotencyInterceptor(uuid: const Uuid());
  });

  group('IdempotencyInterceptor', () {
    test('adds X-Idempotency-Key to POST without one', () {
      final options = RequestOptions(path: '/test', method: 'POST');
      interceptor.onRequest(options, _TestReqHandler());
      expect(options.headers['X-Idempotency-Key'], isNotNull);
      expect(options.headers['X-Idempotency-Key'] as String, isNotEmpty);
    });

    test('does not overwrite existing X-Idempotency-Key on POST', () {
      const existingKey = 'my-existing-key';
      final options = RequestOptions(
        path: '/test',
        method: 'POST',
        headers: {'X-Idempotency-Key': existingKey},
      );
      interceptor.onRequest(options, _TestReqHandler());
      expect(options.headers['X-Idempotency-Key'], equals(existingKey));
    });

    test('does not add X-Idempotency-Key to GET', () {
      final options = RequestOptions(path: '/test', method: 'GET');
      interceptor.onRequest(options, _TestReqHandler());
      expect(options.headers.containsKey('X-Idempotency-Key'), isFalse);
    });

    test('adds X-Idempotency-Key to PUT, PATCH, DELETE', () {
      for (final method in ['PUT', 'PATCH', 'DELETE']) {
        final options = RequestOptions(path: '/test', method: method);
        interceptor.onRequest(options, _TestReqHandler());
        expect(
          options.headers.containsKey('X-Idempotency-Key'),
          isTrue,
          reason: '$method should get a key',
        );
      }
    });
  });
}
