import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/storage/token_storage.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStorage,
    required this.refreshDio,
    required this.onLogout,
    this.onSessionRevoked,
  });

  final TokenStorage tokenStorage;

  // Separate Dio instance with no auth interceptor — avoids circular refresh.
  final Dio refreshDio;

  final Future<void> Function() onLogout;

  /// Called when the server revokes the entire refresh-token family (theft
  /// detection). The callback should notify the user and then call onLogout.
  final Future<void> Function()? onSessionRevoked;

  Future<bool>? _refreshFuture;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenStorage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Collapse concurrent 401s into a single refresh attempt.
    _refreshFuture ??= _doRefresh().whenComplete(() => _refreshFuture = null);

    final success = await _refreshFuture!;
    if (!success) {
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: const UnauthorizedError(),
          type: DioExceptionType.badResponse,
          response: err.response,
        ),
      );
      return;
    }

    // Retry the original request with the new token.
    try {
      final token = await tokenStorage.readAccessToken();
      final opts = err.requestOptions
        ..headers['Authorization'] = 'Bearer $token';
      final response = await refreshDio.fetch<dynamic>(opts);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static String _extractCode(dynamic body) {
    if (body is Map<String, dynamic>) {
      return (body['error'] as Map<String, dynamic>?)?['code'] as String? ?? '';
    }
    return '';
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      await onLogout();
      return false;
    }
    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/token/refresh',
        data: {'refresh_token': refreshToken},
      );
      final body = response.data;
      if (body == null) {
        await onLogout();
        return false;
      }
      await tokenStorage.save(
        accessToken: body['access_token'] as String,
        refreshToken: body['refresh_token'] as String,
        accessExpiresIn: (body['expires_in'] as int?) ?? 900,
      );
      return true;
    } on DioException catch (e) {
      final code = _extractCode(e.response?.data);
      if (code == 'token_family_revoked' && onSessionRevoked != null) {
        await onSessionRevoked!();
      } else {
        await onLogout();
      }
      return false;
    }
  }
}
