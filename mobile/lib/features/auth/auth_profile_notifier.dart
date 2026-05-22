import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:uuid/uuid.dart';

class ProfileState {
  const ProfileState({
    this.nameFirst = '',
    this.nameLast = '',
    this.locale = 'tr-TR',
    this.isLoading = false,
    this.error,
  });

  final String nameFirst;
  final String nameLast;
  final String locale;
  final bool isLoading;
  final AppError? error;

  bool get canSubmit =>
      nameFirst.trim().isNotEmpty &&
      nameLast.trim().isNotEmpty &&
      !isLoading;

  ProfileState copyWith({
    String? nameFirst,
    String? nameLast,
    String? locale,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
  }) {
    return ProfileState(
      nameFirst: nameFirst ?? this.nameFirst,
      nameLast: nameLast ?? this.nameLast,
      locale: locale ?? this.locale,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final authProfileNotifierProvider =
    AutoDisposeNotifierProvider<AuthProfileNotifier, ProfileState>(
  AuthProfileNotifier.new,
);

class AuthProfileNotifier extends AutoDisposeNotifier<ProfileState> {
  @override
  ProfileState build() => const ProfileState();

  void onNameFirstChanged(String v) =>
      state = state.copyWith(nameFirst: v, clearError: true);

  void onNameLastChanged(String v) =>
      state = state.copyWith(nameLast: v, clearError: true);

  void onLocaleChanged(String? v) {
    if (v != null) state = state.copyWith(locale: v);
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final meApi = ref.read(meApiProvider);
      await meApi.updateMe(
        xIdempotencyKey: const Uuid().v7(),
        updateMeRequest: UpdateMeRequest(
          nameFirst: state.nameFirst.trim(),
          nameLast: state.nameLast.trim(),
          locale: state.locale,
        ),
      );
      ref.read(authNotifierProvider.notifier).profileCompleted();
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
