import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/auth_api_ext.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';

class SignInState {
  const SignInState({
    this.isLoading = false,
    this.error,
    this.mfaToken,
    this.maskedPhone,
  });
  final bool isLoading;
  final AppError? error;
  // Non-null means login succeeded but MFA challenge issued.
  final String? mfaToken;
  final String? maskedPhone;

  bool get requiresMFA => mfaToken != null;
  SignInState copyWith({
    bool? isLoading,
    AppError? error,
    bool clearError = false,
    String? mfaToken,
    String? maskedPhone,
  }) =>
      SignInState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        mfaToken: mfaToken ?? this.mfaToken,
        maskedPhone: maskedPhone ?? this.maskedPhone,
      );
}

final signInNotifierProvider =
    NotifierProvider<SignInNotifier, SignInState>(SignInNotifier.new);

class SignInNotifier extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  AuthApiExt get _api => ref.read(authApiExtProvider);

  Future<void> submit({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _api.login(email: email, password: password);
      if (result.requiresMFA) {
        state = SignInState(
          mfaToken: result.mfaToken,
          maskedPhone: result.maskedPhone,
        );
        return;
      }
      await ref.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: result.accessToken!,
            refreshToken: result.refreshToken!,
            expiresIn: result.expiresIn ?? 900,
          );
      state = const SignInState();
    } on DioException catch (e) {
      final err = e.error;
      state = SignInState(
        error: err is AppError
            ? err
            : UnknownError(statusCode: 0, message: e.message ?? ''),
      );
    } catch (e) {
      state = SignInState(
        error: UnknownError(statusCode: 0, message: e.toString()),
      );
    }
  }
}
