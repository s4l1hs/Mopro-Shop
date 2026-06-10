import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/cart/application/cart_merge_service.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';

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
    // Already authed on launch → pull server favorites into the local set
    // (FAV-02 down-sync) without blocking auth resolution.
    unawaited(hydrateFavoritesFromServer(ref));
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
    // Merge guest cart and favorites into server state on login, then pull the
    // server's favorites back down so the local set is the union (FAV-02
    // down-sync → cross-device). Order matters: push up first, then hydrate.
    final guestFavIds = ref.read(favoritesProvider);
    await mergeGuestCart(ref);
    await mergeGuestFavorites(ref, guestFavIds);
    await hydrateFavoritesFromServer(ref);
  }

  Future<void> setLoggedOut() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AsyncData(AuthUnauthenticated());
  }

  void profileCompleted() {
    state = const AsyncData(AuthAuthenticated());
  }
}
