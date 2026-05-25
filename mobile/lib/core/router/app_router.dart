import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/features/account/account_screen.dart';
import 'package:mopro/features/account/cards_screen.dart';
import 'package:mopro/features/account/profile_screen.dart';
import 'package:mopro/features/account/security_screen.dart';
import 'package:mopro/features/address/screens/address_form_screen.dart';
import 'package:mopro/features/address/screens/address_list_screen.dart';
import 'package:mopro/features/auth/login_screen.dart';
import 'package:mopro/features/auth/otp_screen.dart';
import 'package:mopro/features/auth/profile_screen.dart';
import 'package:mopro/features/auth/splash_screen.dart';
import 'package:mopro/features/cart/presentation/cart_screen.dart';
import 'package:mopro/features/catalog/screens/category_products_screen.dart';
import 'package:mopro/features/catalog/screens/category_screen.dart';
import 'package:mopro/features/catalog/screens/home_screen.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/catalog/screens/search_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_address_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_payment_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_redirect_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_result_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_review_screen.dart';
import 'package:mopro/features/favorites/favorites_screen.dart';
import 'package:mopro/features/order/presentation/order_detail_screen.dart';
import 'package:mopro/features/order/presentation/order_history_screen.dart';
import 'package:mopro/features/wallet/plan_detail_screen.dart';
import 'package:mopro/features/wallet/wallet_screen.dart';
import 'package:mopro/shell/app_shell.dart';
import 'package:mopro_api/mopro_api.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _homeNavKey = GlobalKey<NavigatorState>(debugLabel: 'homeNav');
final _categoriesNavKey =
    GlobalKey<NavigatorState>(debugLabel: 'categoriesNav');
final _favoritesNavKey =
    GlobalKey<NavigatorState>(debugLabel: 'favoritesNav');
final _cartNavKey = GlobalKey<NavigatorState>(debugLabel: 'cartNav');
final _accountNavKey = GlobalKey<NavigatorState>(debugLabel: 'accountNav');

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

      // Guard: /checkout and /account/* require authentication
      final needsAuth = loc.startsWith('/checkout') ||
          loc.startsWith('/account') ||
          loc == '/wallet' ||
          loc.startsWith('/wallet/') ||
          loc.startsWith('/orders');

      return switch (auth) {
        null || AuthUnauthenticated() => isAuthRoute
            ? null
            : needsAuth
                ? '/auth/phone?next=${Uri.encodeComponent(loc)}'
                : '/auth/phone',
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
      // ── Wallet (root-level; accessible from account screen) ────────────────
      GoRoute(
        path: '/wallet',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const WalletScreen(),
        routes: [
          GoRoute(
            path: 'plans/:id',
            builder: (_, state) {
              final raw = state.pathParameters['id'];
              final planId = raw != null ? int.tryParse(raw) : null;
              if (planId == null || planId <= 0) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => rootNavigatorKey.currentContext?.go('/wallet'),
                );
                return const WalletScreen();
              }
              return PlanDetailScreen(planId: planId);
            },
          ),
        ],
      ),
      // ── Checkout overlay (full-screen above nav shell) ──────────────────────
      GoRoute(
        path: '/checkout',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const CheckoutAddressScreen(),
        routes: [
          GoRoute(
            path: 'payment',
            builder: (_, __) => const CheckoutPaymentScreen(),
          ),
          GoRoute(
            path: 'review',
            builder: (_, __) => const CheckoutReviewScreen(),
          ),
          GoRoute(
            path: 'redirect',
            builder: (_, state) {
              final invoiceId = (state.extra as String?) ?? '';
              return CheckoutRedirectScreen(invoiceId: invoiceId);
            },
          ),
          GoRoute(
            path: 'result',
            builder: (_, state) {
              final failed =
                  state.uri.queryParameters['failed'] == '1';
              return CheckoutResultScreen(failed: failed);
            },
          ),
        ],
      ),
      // ── Account sub-pages ──────────────────────────────────────────────────
      GoRoute(
        path: '/account/profile',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const AccountProfileScreen(),
      ),
      GoRoute(
        path: '/account/security',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/account/cards',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const CardsScreen(),
      ),
      // ── Orders (root-level for deep links) ─────────────────────────────────
      GoRoute(
        path: '/orders',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) => const OrderHistoryScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) {
              final raw = state.pathParameters['id'];
              final id = raw != null ? int.tryParse(raw) : null;
              if (id == null || id <= 0) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => rootNavigatorKey.currentContext?.go('/orders'),
                );
                return const SizedBox.shrink();
              }
              return OrderDetailScreen(orderId: id);
            },
          ),
        ],
      ),
      // ── Bottom nav shell — 5 tabs: home / categories / favorites / cart / account
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(navigationShell: shell),
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
            navigatorKey: _favoritesNavKey,
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (_, __) => const FavoritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _cartNavKey,
            routes: [
              GoRoute(
                path: '/cart',
                builder: (_, __) => const CartScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _accountNavKey,
            routes: [
              GoRoute(
                path: '/account',
                builder: (_, __) => const AccountScreen(),
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
