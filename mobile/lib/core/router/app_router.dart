import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/bottom_nav_shell.dart';
import 'package:mopro/features/address/screens/address_form_screen.dart';
import 'package:mopro/features/address/screens/address_list_screen.dart';
import 'package:mopro/features/auth/login_screen.dart';
import 'package:mopro/features/auth/otp_screen.dart';
import 'package:mopro/features/auth/profile_screen.dart';
import 'package:mopro/features/auth/splash_screen.dart';
import 'package:mopro/features/catalog/screens/category_products_screen.dart';
import 'package:mopro/features/catalog/screens/category_screen.dart';
import 'package:mopro/features/catalog/screens/home_screen.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/catalog/screens/search_screen.dart';
import 'package:mopro/features/profile/profile_tab_screen.dart';
import 'package:mopro/features/wallet/plan_detail_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:mopro/features/wallet/wallet_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _homeNavKey = GlobalKey<NavigatorState>(debugLabel: 'homeNav');
final _categoriesNavKey =
    GlobalKey<NavigatorState>(debugLabel: 'categoriesNav');
final _walletNavKey = GlobalKey<NavigatorState>(debugLabel: 'walletNav');
final _profileNavKey = GlobalKey<NavigatorState>(debugLabel: 'profileNav');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _AuthStateListenable(ref),
    redirect: (context, state) {
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
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/phone',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (_, state) =>
            OtpScreen(phone: (state.extra as String?) ?? ''),
      ),
      GoRoute(
        path: '/auth/profile',
        builder: (_, __) => const ProfileCompletionScreen(),
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const SearchScreen(),
      ),
      GoRoute(
        path: '/products/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) {
          final raw = state.pathParameters['id'];
          final id = raw != null ? int.tryParse(raw) : null;
          if (id == null || id <= 0) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => rootNavigatorKey.currentContext?.go('/'),
            );
            return const SizedBox.shrink();
          }
          return ProductDetailScreen(productId: id);
        },
      ),
      GoRoute(
        path: '/categories/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) {
          final raw = state.pathParameters['id'];
          final id = raw != null ? int.tryParse(raw) : null;
          if (id == null || id <= 0) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => rootNavigatorKey.currentContext?.go('/categories'),
            );
            return const SizedBox.shrink();
          }
          final name = (state.extra as String?) ?? '';
          return CategoryProductsScreen(categoryId: id, categoryName: name);
        },
      ),
      GoRoute(
        path: '/profile/addresses',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const AddressListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, __) =>
                const AddressFormScreen(editAddress: null),
          ),
          GoRoute(
            path: ':id/edit',
            builder: (_, state) {
              final extra = state.extra;
              return AddressFormScreen(
                editAddress: extra is Address ? extra : null,
              );
            },
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => BottomNavShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeNavKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const CatalogHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _categoriesNavKey,
            routes: [
              GoRoute(
                path: '/categories',
                builder: (_, __) => const CategoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _walletNavKey,
            routes: [
              GoRoute(
                path: '/wallet',
                builder: (_, __) => const WalletScreen(),
                routes: [
                  GoRoute(
                    path: 'plans/:id',
                    builder: (_, state) {
                      final raw = state.pathParameters['id'];
                      final planId =
                          raw != null ? int.tryParse(raw) : null;
                      if (planId == null || planId <= 0) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _walletNavKey.currentContext?.go('/wallet'),
                        );
                        return const WalletScreen();
                      }
                      return PlanDetailScreen(planId: planId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfileTabScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(Ref ref) {
    ref.listen(authNotifierProvider, (_, __) => notifyListeners());
  }
}
