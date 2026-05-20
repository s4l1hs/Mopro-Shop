import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/network/interceptors/error_mapping_interceptor.dart';

// Custom handler: captures rejected error without triggering Dio chain.
class _TestErrHandler extends ErrorInterceptorHandler {
  DioException? captured;

  @override
  void next(DioException err) {}

  @override
  void reject(DioException err) {
    captured = err;
  }

  @override
  void resolve(Response<dynamic> response) {}
}

void main() {
  late ErrorMappingInterceptor interceptor;

  setUp(() {
    interceptor = ErrorMappingInterceptor();
  });

  DioException makeErr(int statusCode, [dynamic body]) {
    final opts = RequestOptions(path: '/test');
    return DioException(
      requestOptions: opts,
      response: Response<dynamic>(
        statusCode: statusCode,
        data: body,
        requestOptions: opts,
        headers: Headers(),
      ),
      type: DioExceptionType.badResponse,
    );
  }

  group('ErrorMappingInterceptor', () {
    test('maps 401 to UnauthorizedError', () {
      final handler = _TestErrHandler();
      interceptor.onError(makeErr(401), handler);
      expect(handler.captured?.error, isA<UnauthorizedError>());
    });

    test('maps 404 to NotFoundError', () {
      final handler = _TestErrHandler();
      interceptor.onError(makeErr(404, {'message': 'not here'}), handler);
      expect(handler.captured?.error, isA<NotFoundError>());
    });

    test('maps 409 to ConflictError with message', () {
      final handler = _TestErrHandler();
      interceptor.onError(
        makeErr(409, {
          'error': {'message': 'duplicate'},
        }),
        handler,
      );
      final err = handler.captured?.error as ConflictError?;
      expect(err?.message, equals('duplicate'));
    });

    test('maps 422 to ValidationError with fields', () {
      final handler = _TestErrHandler();
      interceptor.onError(
        makeErr(422, {
          'error': {
            'message': 'invalid input',
            'fields': [
              {'field': 'phone', 'message': 'required'},
            ],
          },
        }),
        handler,
      );
      final err = handler.captured?.error as ValidationError?;
      expect(err?.message, equals('invalid input'));
      expect(err?.fields, hasLength(1));
      expect(err?.fields.first.field, equals('phone'));
    });

    test('maps 429 to RateLimitedError', () {
      final handler = _TestErrHandler();
      interceptor.onError(makeErr(429), handler);
      expect(handler.captured?.error, isA<RateLimitedError>());
    });

    test('maps 503 system_read_only to SystemReadOnlyError', () {
      final handler = _TestErrHandler();
      interceptor.onError(
        makeErr(503, {
          'error': {'code': 'system_read_only', 'message': 'maintenance'},
        }),
        handler,
      );
      expect(handler.captured?.error, isA<SystemReadOnlyError>());
    });

    test('maps network timeout to NetworkError', () {
      final handler = _TestErrHandler();
      interceptor.onError(
        DioException(
          requestOptions: RequestOptions(path: '/test'),
          type: DioExceptionType.connectionTimeout,
          message: 'timed out',
        ),
        handler,
      );
      expect(handler.captured?.error, isA<NetworkError>());
    });
  });
}
