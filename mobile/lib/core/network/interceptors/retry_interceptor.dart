import 'package:dio/dio.dart';

const _maxAttempts = 3;
const _mutatingMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

class RetryInterceptor extends Interceptor {
  RetryInterceptor({required this.dio});

  final Dio dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final options = err.requestOptions;

    final isServerError =
        err.type == DioExceptionType.badResponse &&
        response != null &&
        response.statusCode != null &&
        response.statusCode! >= 500;

    final isNetworkError =
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout;

    if (!isServerError && !isNetworkError) {
      handler.next(err);
      return;
    }

    // OQ-F: only retry mutating requests if they carry an idempotency key.
    if (_mutatingMethods.contains(options.method.toUpperCase()) &&
        !options.headers.containsKey('X-Idempotency-Key')) {
      handler.next(err);
      return;
    }

    final attempt = (options.extra['_retryAttempt'] as int? ?? 0) + 1;
    if (attempt >= _maxAttempts) {
      handler.next(err);
      return;
    }

    options.extra['_retryAttempt'] = attempt;
    await Future<void>.delayed(Duration(milliseconds: 200 * attempt));

    try {
      final retried = await dio.fetch<dynamic>(options);
      handler.resolve(retried);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
