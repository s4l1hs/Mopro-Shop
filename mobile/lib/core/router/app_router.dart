import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/account/account_screen.dart';
import 'package:mopro/features/account/browsing_history_screen.dart';
import 'package:mopro/features/account/cards_screen.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/account/privacy/privacy_settings_screen.dart';
import 'package:mopro/features/account/profile_screen.dart';
import 'package:mopro/features/account/questions/my_questions_screen.dart';
import 'package:mopro/features/account/reviews/my_reviews_screen.dart';
import 'package:mopro/features/account/security_screen.dart';
import 'package:mopro/features/account/widgets/account_shell.dart';
import 'package:mopro/features/address/screens/address_form_screen.dart';
import 'package:mopro/features/address/screens/address_list_screen.dart';
import 'package:mopro/features/analytics/analytics_service.dart';
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
import 'package:mopro/features/catalog/screens/product_questions_screen.dart';
import 'package:mopro/features/catalog/screens/question_detail_screen.dart';
import 'package:mopro/features/catalog/screens/search_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_address_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_payment_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_redirect_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_result_screen.dart';
import 'package:mopro/features/checkout/presentation/checkout_review_screen.dart';
import 'package:mopro/features/favorites/favorites_screen.dart';
import 'package:mopro/features/help/contact_form_screen.dart';
import 'package:mopro/features/help/help_article_screen.dart';
import 'package:mopro/features/help/help_category_screen.dart';
import 'package:mopro/features/help/help_index_screen.dart';
import 'package:mopro/features/help/help_search_screen.dart';
import 'package:mopro/features/not_found/not_found_screen.dart';
import 'package:mopro/features/notifications/notification_preferences_screen.dart';
import 'package:mopro/features/notifications/notifications_screen.dart';
import 'package:mopro/features/order/presentation/order_detail_screen.dart';
import 'package:mopro/features/order/presentation/order_history_screen.dart';
import 'package:mopro/features/order/presentation/order_return_flow_screen.dart';
import 'package:mopro/features/order/presentation/return_detail_screen.dart';
import 'package:mopro/features/order/presentation/returns_list_screen.dart';
import 'package:mopro/features/seller/screens/seller_dashboard_screen.dart';
import 'package:mopro/features/seller/screens/seller_storefront_screen.dart';
import 'package:mopro/features/seller/user_is_seller_provider.dart';
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
  // Q&A sub-routes must be matched before the generic /products/ product title.
  if (RegExp(r'^/products/\d+/questions/\d+').hasMatch(location)) {
    return t('Soru');
  }
  if (RegExp(r'^/products/\d+/questions/?$').hasMatch(location)) {
    return t('Sorular');
  }
  if (location.startsWith('/products/')) {
    return name == null ? loading : t(name);
  }
  if (location == '/seller/dashboard') return t('Satıcı Paneli');
  if (location == '/seller/returns') return t('İadeler');
  if (location.startsWith('/seller/returns/')) {
    return name == null ? t('İade') : t('İade #$name');
  }
  if (location == '/seller/questions') return t('Sorular');
  if (location.startsWith('/seller/questions/')) return t('Soru');
  if (location.startsWith('/sellers/')) {
    return name == null ? t('Mağaza') : t(name);
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
  if (location == '/account/reviews') return t('Yorumlarım');
  if (location == '/account/questions') return t('Sorularım');
  if (location == '/account/privacy') return t('Gizlilik');
  if (location == '/account/browsing-history') return t('Geçmişim');
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
  if (location == '/help/contact') return t('Bize Ulaş');
  if (location == '/help/search') {
    return name == null || name.isEmpty ? t('Arama') : t('Arama: "$name"');
  }
  if (location.startsWith('/help/category/') || location.startsWith('/help/article/')) {
    return name == null ? t('Yardım') : t(name);
  }
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
      location.startsWith('/account/cards') ||
      location.startsWith('/account/reviews') ||
      location.startsWith('/account/questions') ||
      location.startsWith('/account/privacy') ||
      location.startsWith('/account/browsing-history');

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

/// One-shot snackbar message key set by a redirect (e.g. role-gate denial) and
/// consumed + cleared by the app-root listener. Stores an easy_localization key.
final pendingSnackbarProvider = StateProvider<String?>((_) => null);

/// Role gate for `/seller/*` routes. Returns `/` when a seller route is
/// requested by a non-seller once the role is known; null otherwise.
///
/// [sellerKnown] is false while `/me` is still loading — we defer (null) rather
/// than redirect, to avoid bouncing a seller off their own page mid-fetch (the
/// router re-runs this when currentUserProvider resolves).
String? computeSellerRedirect({
  required String location,
  required bool isSeller,
  required bool sellerKnown,
}) {
  if (!location.startsWith('/seller/')) return null;
  if (!sellerKnown) return null;
  return isSeller ? null : '/';
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
    observers: [
      // Auto-emits page_view on navigation (Tranche 4b instrumentation §6.2).
      AnalyticsNavObserver(() => ref.read(analyticsServiceProvider)),
    ],
    refreshListenable: _AuthStateListenable(ref),
    errorBuilder: (context, state) =>
        NotFoundScreen(attemptedPath: state.uri.toString()),
    redirect: (context, state) {
      final authAsync = ref.read(authNotifierProvider);
      if (authAsync.isLoading) return null;
      final location = state.matchedLocation;
      // Seller role gate (before the generic auth gate so the denial snackbar
      // fires). Deferred while /me is still resolving.
      final sellerGate = computeSellerRedirect(
        location: location,
        isSeller: ref.read(userIsSellerProvider),
        sellerKnown: !ref.read(currentUserProvider).isLoading,
      );
      if (sellerGate != null) {
        ref.read(pendingSnackbarProvider.notifier).state =
            'seller.access_denied';
        return sellerGate;
      }
      return computeAuthRedirect(
        auth: authAsync.valueOrNull,
        location: location,
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
      // Public seller storefront (Tranche 5a). Deep-linkable by slug; guests welcome.
      GoRoute(
        path: '/sellers/:slug',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) {
          final slug = state.pathParameters['slug'] ?? '';
          if (slug.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => rootNavigatorKey.currentContext?.go('/'),
            );
            return const SizedBox.shrink();
          }
          return _titledLoc('/sellers/$slug', SellerStorefrontScreen(slug: slug));
        },
      ),
      // ── Seller panel (role-gated by the top-level redirect; Tranche 5) ────────
      GoRoute(
        path: '/seller/dashboard',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, __) =>
            _titledLoc('/seller/dashboard', const SellerDashboardScreen()),
      ),
      // Public Q&A: standalone questions list + single-question thread. Reads
      // are open to guests; the ask/answer CTAs gate via the login presenter.
      GoRoute(
        path: '/products/:id/questions',
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
            '/products/$id/questions',
            ProductQuestionsScreen(productId: id),
          );
        },
        routes: [
          GoRoute(
            path: ':qid',
            builder: (_, state) {
              final pRaw = state.pathParameters['id'];
              final qRaw = state.pathParameters['qid'];
              final pid = pRaw != null ? int.tryParse(pRaw) : null;
              final qid = qRaw != null ? int.tryParse(qRaw) : null;
              if (pid == null || pid <= 0 || qid == null || qid <= 0) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => rootNavigatorKey.currentContext?.go('/'),
                );
                return const SizedBox.shrink();
              }
              return _titledLoc(
                '/products/$pid/questions/$qid',
                QuestionDetailScreen(productId: pid, questionId: qid),
              );
            },
          ),
        ],
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
            path: '/account/reviews',
            builder: (_, __) => const MyReviewsScreen(),
          ),
          GoRoute(
            path: '/account/questions',
            builder: (_, __) => const MyQuestionsScreen(),
          ),
          GoRoute(
            path: '/account/privacy',
            builder: (_, __) => const PrivacySettingsScreen(),
          ),
          GoRoute(
            path: '/account/browsing-history',
            builder: (_, __) => const BrowsingHistoryScreen(),
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
            builder: (_, __) => const HelpIndexScreen(),
            routes: [
              GoRoute(
                path: 'category/:slug',
                builder: (_, state) =>
                    HelpCategoryScreen(slug: state.pathParameters['slug'] ?? ''),
              ),
              GoRoute(
                path: 'article/:slug',
                builder: (_, state) =>
                    HelpArticleScreen(slug: state.pathParameters['slug'] ?? ''),
              ),
              GoRoute(
                path: 'search',
                builder: (_, state) => HelpSearchScreen(
                  query: state.uri.queryParameters['q'] ?? '',
                ),
              ),
              GoRoute(
                path: 'contact',
                builder: (_, state) {
                  final orderRaw = state.uri.queryParameters['order'];
                  return ContactFormScreen(
                    articleSlug: state.uri.queryParameters['article'],
                    orderId: orderRaw != null ? int.tryParse(orderRaw) : null,
                  );
                },
              ),
            ],
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
    ref
      ..listen(authNotifierProvider, (_, __) => notifyListeners())
      // Re-run redirects when /me resolves so the deferred seller gate decides.
      ..listen(currentUserProvider, (_, __) => notifyListeners());
  }
}
