import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/account/account_placeholder_screen.dart';
import 'package:mopro/features/account/account_screen.dart';
import 'package:mopro/features/account/cards_screen.dart';
import 'package:mopro/features/account/profile_screen.dart';
import 'package:mopro/features/account/security_screen.dart';
import 'package:mopro/features/account/widgets/account_shell.dart';
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
import 'package:mopro/features/not_found/not_found_screen.dart';
import 'package:mopro/features/notifications/notification_preferences_screen.dart';
import 'package:mopro/features/notifications/notifications_screen.dart';
import 'package:mopro/features/order/presentation/order_detail_screen.dart';
import 'package:mopro/features/order/presentation/order_history_screen.dart';
import 'package:mopro/features/order/presentation/order_return_flow_screen.dart';
import 'package:mopro/features/order/presentation/return_detail_screen.dart';
import 'package:mopro/features/order/presentation/returns_list_screen.dart';
import 'package:mopro/features/wallet/plan_detail_screen.dart';
import 'package:mopro/features/wallet/wallet_screen.dart';
import 'package:mopro/shell/app_shell.dart';
import 'package:mopro_api/mopro_api.dart';

/// Wraps a screen in [Title] so the browser tab shows "Mopro · <page>".
Widget _titled(String page, Widget child) => Title(
      title: 'Mopro · $page',
      color: MoproTokens.primaryLight,
      child: child,
    );

/// Wraps [child] in a [Title] resolved from [location] (and optional dynamic
/// [name], e.g. a product title or order id).
Widget _titledLoc(String location, Widget child, {String? name}) => Title(
      title: moproPageTitle(location, name: name),
      color: MoproTokens.primaryLight,
      child: child,
    );

/// Pure resolver for the browser tab title of [location]. Dynamic routes accept
/// a [name] (product title, category name, order id, search query) and fall back
/// to "Mopro · Yükleniyor…" while it resolves. Unknown → "Mopro · Sayfa Bulunamadı".
String moproPageTitle(String location, {String? name}) {
  String t(String s) => 'Mopro · $s';
  final loading = t('Yükleniyor…');

  // Specific prefixes first.
  if (location.startsWith('/categories/')) {
    return name == null ? loading : t(name);
  }
  if (location.startsWith('/products/')) {
    return name == null ? loading : t(name);
  }
  if (location.startsWith('/checkout/result')) return t('Sipariş Sonucu');
  if (location.startsWith('/checkout')) return t('Ödeme');
  if (location == '/profile/addresses/new') return t('Yeni Adres');
  if (location.startsWith('/profile/addresses/')) return t('Adresi Düzenle');
  if (location == '/profile/addresses') return t('Adreslerim');
  if (location.startsWith('/wallet/plans/')) return t('Kampanya Detayı');
  if (location == '/wallet') return t('Cüzdan');
  if (location == '/orders') return t('Siparişlerim');
  if (location.endsWith('/return')) return t('İade Talebi');
  if (location.startsWith('/orders/')) {
    return name == null ? t('Siparişlerim') : t('Sipariş #$name');
  }
  if (location == '/returns') return t('İadelerim');
  if (location.startsWith('/returns/')) {
    return name == null ? t('İadelerim') : t('İade #$name');
  }
  if (location == '/account/profile') return t('Profilim');
  if (location == '/account/security') return t('Güvenlik');
  if (location == '/account/cards') return t('Kartlarım');
  if (location == '/account/notifications/preferences') {
    return t('Bildirim Ayarları');
  }
  if (location == '/account/notifications') return t('Bildirimler');
  if (location == '/account') return t('Hesabım');
  if (location == '/categories') return t('Kategoriler');
  if (location == '/search') {
    return name == null || name.isEmpty ? t('Arama') : t('"$name" araması');
  }
  if (location == '/cart') return t('Sepetim');
  if (location == '/favorites') return t('Favorilerim');
  if (location == '/auth/login') return t('Giriş');
  if (location == '/auth/register') return t('Üye Ol');
  if (location == '/auth/verify-email') return t('E-posta Doğrulama');
  if (location == '/auth/forgot-password') return t('Şifre Sıfırlama');
  if (location == '/auth/mfa') return t('İki Faktör');
  if (location == '/auth/profile') return t('Profil Tamamlama');
  if (location == '/help') return t('Yardım');
  if (location == '/' || location == '/splash') return 'Mopro';
  return t('Sayfa Bulunamadı');
}

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
      location.startsWith('/returns') ||
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
final _accountShellNavKey =
    GlobalKey<NavigatorState>(debugLabel: 'accountShellNav');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: _AuthStateListenable(ref),
    errorBuilder: (context, state) =>
        NotFoundScreen(attemptedPath: state.uri.toString()),
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
        builder: (_, __) => _titledLoc('/auth/login', const SignInScreen()),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (_, __) => _titledLoc('/auth/register', const SignUpScreen()),
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
        builder: (_, state) => _titledLoc(
          '/search',
          const SearchScreen(),
          name: state.uri.queryParameters['q'],
        ),
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
          return _titledLoc(
            '/products/$id',
            ProductDetailScreen(productId: id),
          );
        },
      ),
      // Full-screen multi-step return flow (outside the account shell).
      GoRoute(
        path: '/orders/:id/return',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) {
          final raw = state.pathParameters['id'];
          final id = raw != null ? int.tryParse(raw) : null;
          if (id == null || id <= 0) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => rootNavigatorKey.currentContext?.go('/orders'),
            );
            return const SizedBox.shrink();
          }
          return _titledLoc(
            '/orders/$id/return',
            OrderReturnFlowScreen(
              orderId: id,
              initialStep: state.uri.queryParameters['step'],
            ),
          );
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
      // ── Checkout overlay (full-screen above nav shell) ─────────────────
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
      // ── Account section shell — desktop/tablet two-pane (Option A) ─────────
      // Wraps the account sub-pages + orders/wallet/addresses. On mobile the
      // AccountShell builder is a pass-through, so these render full-screen with
      // their own app bars exactly as before (list-then-detail unchanged). On
      // tablet/desktop it renders WebHeader + rail + pane with the child's app
      // bar suppressed via AccountChromeScope. The auth guard (computeAuthRedirect)
      // still applies at the route level — the shell adds no second check.
      // `/account` itself stays the bottom-nav tab below (AccountScreen handles
      // its own desktop two-pane via ResponsiveBuilder).
      ShellRoute(
        navigatorKey: _accountShellNavKey,
        builder: (_, state, child) =>
            _titledLoc(state.matchedLocation, AccountShell(child: child)),
        routes: [
          GoRoute(
            path: '/account/profile',
            builder: (_, __) => const AccountProfileScreen(),
          ),
          GoRoute(
            path: '/account/security',
            builder: (_, __) => const SecurityScreen(),
          ),
          GoRoute(
            path: '/account/cards',
            builder: (_, __) => const CardsScreen(),
          ),
          GoRoute(
            path: '/account/notifications',
            builder: (_, __) => const NotificationsScreen(),
            routes: [
              GoRoute(
                path: 'preferences',
                builder: (_, __) => const NotificationPreferencesScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/help',
            builder: (_, __) => const AccountPlaceholderScreen(
              titleKey: 'account.menu_help',
              icon: Icons.help_outline_rounded,
            ),
          ),
          GoRoute(
            path: '/orders',
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
          GoRoute(
            path: '/returns',
            builder: (_, __) => const ReturnsListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) {
                  final raw = state.pathParameters['id'];
                  final id = raw != null ? int.tryParse(raw) : null;
                  if (id == null || id <= 0) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => rootNavigatorKey.currentContext?.go('/returns'),
                    );
                    return const SizedBox.shrink();
                  }
                  return ReturnDetailScreen(returnId: id);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/wallet',
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
          GoRoute(
            path: '/profile/addresses',
            builder: (_, __) => const AddressListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const AddressFormScreen(),
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
                builder: (_, __) =>
                    _titled('Ana Sayfa', const CatalogHomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _categoriesNavKey,
            routes: [
              GoRoute(
                path: '/categories',
                builder: (_, __) =>
                    _titled('Kategoriler', const CategoryScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _favoritesNavKey,
            routes: [
              GoRoute(
                path: '/favorites',
                builder: (_, __) =>
                    _titled('Favorilerim', const FavoritesScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _cartNavKey,
            routes: [
              GoRoute(
                path: '/cart',
                builder: (_, __) =>
                    _titled('Sepetim', const CartScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _accountNavKey,
            routes: [
              GoRoute(
                path: '/account',
                builder: (_, __) =>
                    _titled('Hesabım', const AccountScreen()),
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
