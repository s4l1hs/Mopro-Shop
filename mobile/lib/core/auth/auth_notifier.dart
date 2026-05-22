import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final storage = ref.watch(tokenStorageProvider);
    final token = await storage.readAccessToken();
    if (token == null) return const AuthUnauthenticated();

    final expiresAt = await storage.readAccessExpiresAt();
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      // Expired — treat as unauthenticated; AuthInterceptor will refresh on
      // the next real request, but route guard should send user to auth flow.
      return const AuthUnauthenticated();
    }
    return const AuthAuthenticated();
  }

  Future<void> setAuthenticated({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
    bool profileComplete = true,
  }) async {
    final storage = ref.read(tokenStorageProvider);
    await storage.save(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresIn: expiresIn,
    );
    state = AsyncData(
      profileComplete
          ? const AuthAuthenticated()
          : const AuthProfileIncomplete(),
    );
  }

  Future<void> setLoggedOut() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(AuthUnauthenticated());
  }

  void profileCompleted() {
    state = const AsyncData(AuthAuthenticated());
  }
}
