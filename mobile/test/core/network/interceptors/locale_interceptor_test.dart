import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/network/interceptors/locale_interceptor.dart';

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
  group('LocaleInterceptor', () {
    test('sets Accept-Language from localeGetter', () {
      final interceptor = LocaleInterceptor(
        localeGetter: () => const Locale('tr', 'TR'),
      );
      final options = RequestOptions(path: '/test', method: 'GET');
      interceptor.onRequest(options, _TestReqHandler());
      expect(options.headers['Accept-Language'], equals('tr-TR'));
    });

    test('reflects locale change on next request', () {
      var currentLocale = const Locale('tr', 'TR');
      final interceptor = LocaleInterceptor(localeGetter: () => currentLocale);

      final opts1 = RequestOptions(path: '/a', method: 'GET');
      interceptor.onRequest(opts1, _TestReqHandler());
      expect(opts1.headers['Accept-Language'], equals('tr-TR'));

      currentLocale = const Locale('en', 'US');
      final opts2 = RequestOptions(path: '/b', method: 'GET');
      interceptor.onRequest(opts2, _TestReqHandler());
      expect(opts2.headers['Accept-Language'], equals('en-US'));
    });
  });
}
