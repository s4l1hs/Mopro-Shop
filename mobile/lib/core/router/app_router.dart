import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/router/auth_guard.dart';
import 'package:mopro/features/auth/login_screen.dart';
import 'package:mopro/features/auth/otp_screen.dart';
import 'package:mopro/features/home/home_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    refreshListenable: _AuthStateListenable(ref),
    redirect: (context, state) {
      // While loading, stay put; SplashScreen handles the wait.
      if (authState.isLoading) return null;

      final auth = authState.valueOrNull;
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/auth');

      return switch (auth) {
        null || AuthUnauthenticated() =>
          isAuthRoute ? null : '/auth/phone',
        AuthProfileIncomplete() =>
          loc == '/auth/profile' ? null : '/auth/profile',
        AuthAuthenticated() =>
          isAuthRoute ? '/' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/phone',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (context, state) => const OtpScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod state changes into GoRouter's refreshListenable.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(Ref ref) {
    ref.listen(authNotifierProvider, (_, __) => notifyListeners());
  }
}
