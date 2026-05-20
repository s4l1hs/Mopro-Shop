import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/network/interceptors/trace_interceptor.dart';
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
  group('TraceInterceptor', () {
    test('adds X-Trace-Id to every request', () {
      final interceptor = TraceInterceptor(uuid: const Uuid());
      final options = RequestOptions(path: '/test', method: 'GET');
      interceptor.onRequest(options, _TestReqHandler());
      final traceId = options.headers['X-Trace-Id'] as String?;
      expect(traceId, isNotNull);
      expect(traceId, isNotEmpty);
    });

    test('generates distinct trace IDs for successive requests', () {
      final interceptor = TraceInterceptor(uuid: const Uuid());
      final opts1 = RequestOptions(path: '/a', method: 'GET');
      final opts2 = RequestOptions(path: '/b', method: 'GET');
      interceptor
        ..onRequest(opts1, _TestReqHandler())
        ..onRequest(opts2, _TestReqHandler());
      expect(
        opts1.headers['X-Trace-Id'],
        isNot(equals(opts2.headers['X-Trace-Id'])),
      );
    });
  });
}
