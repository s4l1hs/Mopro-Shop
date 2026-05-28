import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/auth_api_ext.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';

class MFAState {
  const MFAState({
    this.isLoading = false,
    this.error,
  });
  final bool isLoading;
  final AppError? error;

  MFAState copyWith({
    bool? isLoading,
    AppError? error,
    bool clearError = false,
  }) =>
      MFAState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
      );
}

final mfaNotifierProvider =
    NotifierProvider<MFANotifier, MFAState>(MFANotifier.new);

class MFANotifier extends Notifier<MFAState> {
  @override
  MFAState build() => const MFAState();

  AuthApiExt get _api => ref.read(authApiExtProvider);

  Future<void> verify({
    required String mfaToken,
    required String code,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _api.verifyMFA(mfaToken: mfaToken, code: code);
      await ref.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: result.accessToken!,
            refreshToken: result.refreshToken!,
            expiresIn: result.expiresIn ?? 900,
          );
      state = const MFAState();
    } on DioException catch (e) {
      final err = e.error;
      state = MFAState(
        error: err is AppError
            ? err
            : UnknownError(statusCode: 0, message: e.message ?? ''),
      );
    }
  }
}
