import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/auth_api_ext.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';

class ForgotPasswordState {
  const ForgotPasswordState({
    this.isLoading = false,
    this.sent = false,
    this.error,
  });
  final bool isLoading;
  final bool sent;
  final AppError? error;
}

final forgotPasswordNotifierProvider =
    NotifierProvider<ForgotPasswordNotifier, ForgotPasswordState>(
  ForgotPasswordNotifier.new,
);

class ForgotPasswordNotifier extends Notifier<ForgotPasswordState> {
  @override
  ForgotPasswordState build() => const ForgotPasswordState();

  AuthApiExt get _api => ref.read(authApiExtProvider);

  Future<void> submit({required String email}) async {
    state = const ForgotPasswordState(isLoading: true);
    try {
      await _api.forgotPassword(email: email);
      state = const ForgotPasswordState(sent: true);
    } on DioException catch (_) {
      // Always show success — server never reveals if email exists.
      state = const ForgotPasswordState(sent: true);
    }
  }
}
