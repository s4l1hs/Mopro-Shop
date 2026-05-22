import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

class PhoneState {
  const PhoneState({
    this.rawDigits = '',
    this.isLoading = false,
    this.error,
    this.submittedPhone,
  });

  final String rawDigits;
  final bool isLoading;
  final AppError? error;

  /// Non-null after a successful OTP request — widget navigates to OTP screen.
  final String? submittedPhone;

  PhoneState copyWith({
    String? rawDigits,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
    String? submittedPhone,
  }) {
    return PhoneState(
      rawDigits: rawDigits ?? this.rawDigits,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      submittedPhone: submittedPhone ?? this.submittedPhone,
    );
  }

  bool get canSubmit => rawDigits.length == 10 && !isLoading;
}

final authPhoneNotifierProvider =
    AutoDisposeNotifierProvider<AuthPhoneNotifier, PhoneState>(
  AuthPhoneNotifier.new,
);

class AuthPhoneNotifier extends AutoDisposeNotifier<PhoneState> {
  @override
  PhoneState build() => const PhoneState();

  void onPhoneChanged(String digits) {
    state = state.copyWith(rawDigits: digits, clearError: true);
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;
    final phone = '+90${state.rawDigits}';
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final api = ref.read(authApiProvider);
      await api.requestOtp(
        requestOtpRequest: RequestOtpRequest(phone: phone),
      );
      state = state.copyWith(isLoading: false, submittedPhone: phone);
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
}
