import 'package:dio/dio.dart';
import 'package:mopro/core/network/app_error.dart';

class ErrorMappingInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final appError = _map(err);
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: appError,
      ),
    );
  }

  AppError _map(DioException err) {
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return NetworkError(message: err.message ?? 'network error');
    }

    final response = err.response;
    if (response == null) {
      return NetworkError(message: err.message ?? 'no response');
    }

    final statusCode = response.statusCode ?? 0;
    final body = response.data;

    // Manual JSON parsing — avoids build_runner dependency in
    // the interceptor layer.
    final message = _extractMessage(body);
    final code = _extractCode(body);

    return switch (statusCode) {
      401 when code == 'token_family_revoked' => const SessionRevokedError(),
      401 => const UnauthorizedError(),
      404 => NotFoundError(resource: message),
      409 => ConflictError(message: message),
      422 when code == 'otp_invalid' => const OtpInvalidError(),
      422 when code == 'otp_expired' => const OtpExpiredError(),
      422 => ValidationError(
          message: message,
          fields: _extractFields(body),
        ),
      423 => const PhoneLockedError(),
      429 when code == 'rate_limit_exceeded' => const OtpExhaustedError(),
      429 => RateLimitedError(
          retryAfterSeconds: _extractRetryAfter(response.headers),
        ),
      503 when code == 'system_read_only' => const SystemReadOnlyError(),
      _ => UnknownError(statusCode: statusCode, message: message),
    };
  }

  String _extractMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      return (body['error'] as Map<String, dynamic>?)?['message'] as String? ??
          body['message'] as String? ??
          'unknown error';
    }
    return body?.toString() ?? 'unknown error';
  }

  String _extractCode(dynamic body) {
    if (body is Map<String, dynamic>) {
      return (body['error'] as Map<String, dynamic>?)?['code'] as String? ?? '';
    }
    return '';
  }

  List<FieldError> _extractFields(dynamic body) {
    if (body is! Map<String, dynamic>) return const [];
    final rawFields =
        (body['error'] as Map<String, dynamic>?)?['fields'] as List<dynamic>?;
    if (rawFields == null) return const [];
    return rawFields
        .whereType<Map<String, dynamic>>()
        .map(
          (f) => FieldError(
            field: f['field'] as String? ?? '',
            message: f['message'] as String? ?? '',
          ),
        )
        .toList();
  }

  int? _extractRetryAfter(Headers headers) {
    final value = headers.value('retry-after');
    return value != null ? int.tryParse(value) : null;
  }
}
