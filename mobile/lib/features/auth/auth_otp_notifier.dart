import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:uuid/uuid.dart';

class OtpState {
  const OtpState({
    required this.phone,
    this.code = '',
    this.isLoading = false,
    this.error,
    this.verified = false,
    this.resendCountdown = 0,
  });

  final String phone;
  final String code;
  final bool isLoading;
  final AppError? error;

  /// True after successful verification — widget navigates away.
  final bool verified;

  /// Seconds remaining before the user may resend the OTP.
  final int resendCountdown;

  bool get canSubmit => code.length == 6 && !isLoading;
  bool get canResend => resendCountdown == 0 && !isLoading;

  OtpState copyWith({
    String? code,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
    bool? verified,
    int? resendCountdown,
  }) {
    return OtpState(
      phone: phone,
      code: code ?? this.code,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      verified: verified ?? this.verified,
      resendCountdown: resendCountdown ?? this.resendCountdown,
    );
  }
}

final authOtpNotifierProvider = AutoDisposeNotifierProviderFamily<
    AuthOtpNotifier, OtpState, String>(AuthOtpNotifier.new);

class AuthOtpNotifier extends AutoDisposeFamilyNotifier<OtpState, String> {
  Timer? _resendTimer;

  @override
  OtpState build(String phone) {
    ref.onDispose(() => _resendTimer?.cancel());
    _startResendCountdown();
    return OtpState(phone: phone, resendCountdown: 60);
  }

  void onCodeChanged(String code) {
    state = state.copyWith(code: code, clearError: true);
    if (code.length == 6) submit();
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final api = ref.read(authApiProvider);
      final response = await api.verifyOtp(
        xIdempotencyKey: const Uuid().v7(),
        verifyOtpRequest: VerifyOtpRequest(
          phone: state.phone,
          code: state.code,
        ),
      );
      final pair = response.data!;
      await ref.read(authNotifierProvider.notifier).setAuthenticated(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken,
            expiresIn: pair.expiresIn,
          );
      state = state.copyWith(isLoading: false, verified: true);
    } on DioException catch (e) {
      final err = e.error;
      final appError = err is AppError
          ? err
          : NetworkError(message: e.message ?? 'network error');
      state = state.copyWith(isLoading: false, error: appError);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: UnknownError(statusCode: 0, message: e.toString()),
      );
    }
  }

  Future<void> resend() async {
    if (!state.canResend) return;
    state = state.copyWith(clearError: true);
    try {
      final api = ref.read(authApiProvider);
      await api.requestOtp(
        requestOtpRequest: RequestOtpRequest(phone: state.phone),
      );
      _startResendCountdown();
    } on DioException catch (e) {
      final err = e.error;
      final appError = err is AppError
          ? err
          : NetworkError(message: e.message ?? 'network error');
      state = state.copyWith(error: appError);
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    state = state.copyWith(resendCountdown: 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.resendCountdown - 1;
      if (remaining <= 0) {
        _resendTimer?.cancel();
        state = state.copyWith(resendCountdown: 0);
      } else {
        state = state.copyWith(resendCountdown: remaining);
      }
    });
  }
}
