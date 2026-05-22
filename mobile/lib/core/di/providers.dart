import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/network/dio_client.dart';
import 'package:mopro/core/network/interceptors/auth_interceptor.dart';
import 'package:mopro/core/storage/token_storage.dart';
import 'package:mopro_api/mopro_api.dart';

// Overridden at app startup via ProviderScope (from dart-define API_BASE_URL).
final apiBaseUrlProvider = Provider<String>(
  (_) => 'https://api.moproshop.com',
);

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(ref.watch(secureStorageProvider));
});

final localeStateProvider = StateProvider<Locale>((ref) {
  return const Locale('tr', 'TR');
});

final authInterceptorProvider = Provider<AuthInterceptor>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final logoutFn = ref.watch(_logoutFnProvider);

  final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
  return AuthInterceptor(
    tokenStorage: storage,
    refreshDio: refreshDio,
    onLogout: logoutFn,
    onSessionRevoked: () async {
      ref.read(sessionRevokedProvider.notifier).state = true;
      await ref.read(authNotifierProvider.notifier).setLoggedOut();
    },
  );
});

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final storage = ref.watch(tokenStorageProvider);
  final locale = ref.watch(localeStateProvider);

  return buildDio(
    baseUrl: baseUrl,
    tokenStorage: storage,
    localeGetter: () => locale,
    onLogout: ref.watch(_logoutFnProvider),
    onSessionRevoked: () async {
      ref.read(sessionRevokedProvider.notifier).state = true;
      await ref.read(authNotifierProvider.notifier).setLoggedOut();
    },
  );
});

/// True when the server revokes a refresh-token family (theft detection).
/// Root widget shows the ErrorBanner once, then resets to false.
final sessionRevokedProvider = StateProvider<bool>((_) => false);

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioProvider));
});

final meApiProvider = Provider<MeApi>((ref) {
  return MeApi(ref.watch(dioProvider));
});

final _logoutFnProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(authNotifierProvider.notifier).setLoggedOut();
  };
});
