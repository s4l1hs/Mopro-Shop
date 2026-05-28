import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/auth_api_ext.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';

class SignUpState {
  const SignUpState({
    this.isLoading = false,
    this.error,
    this.registered = false,
  });
  final bool isLoading;
  final AppError? error;
  final bool registered;

  SignUpState copyWith({
    bool? isLoading,
    AppError? error,
    bool clearError = false,
    bool? registered,
  }) =>
      SignUpState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : error ?? this.error,
        registered: registered ?? this.registered,
      );
}

final signUpNotifierProvider =
    NotifierProvider<SignUpNotifier, SignUpState>(SignUpNotifier.new);

class SignUpNotifier extends Notifier<SignUpState> {
  @override
  SignUpState build() => const SignUpState();

  AuthApiExt get _api => ref.read(authApiExtProvider);

  Future<void> submit({
    required String email,
    required String password,
    required String nameFirst,
    required String nameLast,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _api.register(
        email: email,
        password: password,
        nameFirst: nameFirst,
        nameLast: nameLast,
      );
      state = state.copyWith(isLoading: false, registered: true);
    } on DioException catch (e) {
      state = SignUpState(
        error: e.error is AppError
            ? e.error! as AppError
            : UnknownError(statusCode: 0, message: e.message ?? ''),
      );
    } catch (e) {
      state = SignUpState(
        error: UnknownError(statusCode: 0, message: e.toString()),
      );
    }
  }
}
