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
import 'package:mopro/features/auth/email_verify_screen.dart';
import 'package:mopro/features/auth/forgot_password_screen.dart';
import 'package:mopro/features/auth/mfa_challenge_screen.dart';
import 'package:mopro/features/auth/profile_screen.dart';
import 'package:mopro/features/auth/sign_in_screen.dart';
import 'package:mopro/features/auth/sign_up_screen.dart';
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

/// Pure function exposing the auth-aware redirect rules.
/// Returns the redirect target, or null if the user may stay at [location].
///
/// Rules:
///   - Unauthenticated guests can browse public routes (home, categories,
///     PDP, search, favorites, cart, account tab).
///   - Hard-gated routes (checkout, orders, wallet, addresses, account
///     sub-pages) redirect to `/auth/login?next=<location>` for guests.
///   - Profile-incomplete users are forced to `/auth/profile`.
///   - Fully authenticated users on /auth/* are redirected back to `/`.
String? computeAuthRedirect({
  required AuthState? auth,
  required String location,
}) {
  final isAuthRoute = location.startsWith('/auth');
  final hardGated = location.startsWith('/checkout') ||
      location == '/wallet' ||
      location.startsWith('/wallet/') ||
      location.startsWith('/orders') ||
      location.startsWith('/profile/addresses') ||
      location.startsWith('/account/profile') ||
      location.startsWith('/account/security') ||
      location.startsWith('/account/cards');

  return switch (auth) {
    null || AuthUnauthenticated() => isAuthRoute
        ? null
        : hardGated
            ? '/auth/login?next=${Uri.encodeComponent(location)}'
            : null,
    AuthProfileIncomplete() =>
      location == '/auth/profile' ? null : '/auth/profile',
    AuthAuthenticated() => isAuthRoute ? '/' : null,
  };
}

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
      return computeAuthRedirect(
        auth: authAsync.valueOrNull,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      // ── New email auth routes ──────────────────────────────────────────────
      GoRoute(
        path: '/auth/login',
        builder: (_, __) => const SignInScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, __) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/auth/verify-email',
        builder: (_, state) => EmailVerifyScreen(
          email: (state.extra as String?) ?? '',
        ),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/mfa',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return MFAChallengeScreen(
            mfaToken: extra['mfa_token'] as String? ?? '',
            maskedPhone: extra['masked_phone'] as String? ?? '',
          );
        },
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
