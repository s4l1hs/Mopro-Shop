import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/network/interceptors/auth_interceptor.dart';
import 'package:mopro/core/network/interceptors/error_mapping_interceptor.dart';
import 'package:mopro/core/network/interceptors/idempotency_interceptor.dart';
import 'package:mopro/core/network/interceptors/locale_interceptor.dart';
import 'package:mopro/core/network/interceptors/retry_interceptor.dart';
import 'package:mopro/core/network/interceptors/trace_interceptor.dart';
import 'package:mopro/core/storage/token_storage.dart';

Dio buildDio({
  required String baseUrl,
  required TokenStorage tokenStorage,
  required Locale Function() localeGetter,
  required Future<void> Function() onLogout,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));

  // Minimal Dio for token refresh — no auth interceptor to avoid circularity.
  final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));

  final authInterceptor = AuthInterceptor(
    tokenStorage: tokenStorage,
    refreshDio: refreshDio,
    onLogout: onLogout,
  );

  // Add order: Idempotency → Trace → Locale → Auth → Retry → ErrorMapping
  dio.interceptors
    ..add(IdempotencyInterceptor())
    ..add(TraceInterceptor())
    ..add(LocaleInterceptor(localeGetter: localeGetter))
    ..add(authInterceptor)
    ..add(RetryInterceptor(dio: dio))
    ..add(ErrorMappingInterceptor());

  return dio;
}
