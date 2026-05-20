import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class LocaleInterceptor extends Interceptor {
  LocaleInterceptor({required this.localeGetter});

  final Locale Function() localeGetter;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final locale = localeGetter();
    options.headers['Accept-Language'] =
        '${locale.languageCode}-${locale.countryCode}';
    handler.next(options);
  }
}
