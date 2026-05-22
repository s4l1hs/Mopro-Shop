import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/router/auth_guard.dart';
import 'package:mopro/features/auth/login_screen.dart';
import 'package:mopro/features/auth/otp_screen.dart';
import 'package:mopro/features/auth/profile_screen.dart';
import 'package:mopro/features/auth/splash_screen.dart';
import 'package:mopro/features/home/home_screen.dart';
import 'package:mopro/features/wallet/plan_detail_screen.dart';
import 'package:mopro/features/wallet/wallet_screen.dart';

/// Top-level navigator key — use for imperative navigation outside widget tree.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Use refreshListenable so the router is created ONCE and only re-runs
  // its redirect when auth state changes, without recreating the GoRouter.
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: _AuthStateListenable(ref),
    redirect: (context, state) {
      // Read (not watch) current auth state inside redirect callback.
      final authAsync = ref.read(authNotifierProvider);

      if (authAsync.isLoading) return null;

      final auth = authAsync.valueOrNull;
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/auth');

      return switch (auth) {
        null || AuthUnauthenticated() =>
          isAuthRoute ? null : '/auth/phone',
        AuthProfileIncomplete() =>
          loc == '/auth/profile' ? null : '/auth/profile',
        AuthAuthenticated() => isAuthRoute ? '/' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
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
        builder: (context, state) => OtpScreen(
          phone: (state.extra as String?) ?? '',
        ),
      ),
      GoRoute(
        path: '/auth/profile',
        builder: (context, state) => const ProfileCompletionScreen(),
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const WalletScreen(),
        routes: [
          GoRoute(
            path: 'plans/:id',
            builder: (context, state) {
              final raw = state.pathParameters['id'];
              final planId = raw != null ? int.tryParse(raw) : null;
              if (planId == null || planId <= 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) context.go('/wallet');
                });
                return const WalletScreen();
              }
              return PlanDetailScreen(planId: planId);
            },
          ),
        ],
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
