import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/router/app_router.dart';

void main() {
  group('computeAuthRedirect — guest browsing (public)', () {
    const publicRoutes = [
      '/',
      '/categories',
      '/categories/12',
      '/products/42',
      '/search',
      '/favorites',
      '/cart',
      '/account',
    ];

    for (final route in publicRoutes) {
      test('guest may stay on $route', () {
        expect(
          computeAuthRedirect(
            auth: const AuthUnauthenticated(),
            location: route,
          ),
          isNull,
        );
      });
    }

    test('null auth state treated same as unauthenticated', () {
      expect(
        computeAuthRedirect(auth: null, location: '/categories/7'),
        isNull,
      );
    });
  });

  group('computeAuthRedirect — hard-gated redirects', () {
    const gatedRoutes = [
      '/checkout',
      '/checkout/payment',
      '/checkout/review',
      '/orders',
      '/orders/99',
      '/wallet',
      '/wallet/plans/1',
      '/profile/addresses',
      '/profile/addresses/new',
      '/account/profile',
      '/account/security',
      '/account/cards',
    ];

    for (final route in gatedRoutes) {
      test('guest visiting $route redirects to /auth/login with next=', () {
        final result = computeAuthRedirect(
          auth: const AuthUnauthenticated(),
          location: route,
        );
        expect(result, isNotNull);
        expect(result, startsWith('/auth/login?next='));
        expect(result, contains(Uri.encodeComponent(route)));
      });
    }
  });

  group('computeAuthRedirect — auth state transitions', () {
    test('AuthProfileIncomplete forces /auth/profile from any other route', () {
      expect(
        computeAuthRedirect(
          auth: const AuthProfileIncomplete(),
          location: '/',
        ),
        '/auth/profile',
      );
      expect(
        computeAuthRedirect(
          auth: const AuthProfileIncomplete(),
          location: '/categories',
        ),
        '/auth/profile',
      );
    });

    test('AuthProfileIncomplete already on /auth/profile stays', () {
      expect(
        computeAuthRedirect(
          auth: const AuthProfileIncomplete(),
          location: '/auth/profile',
        ),
        isNull,
      );
    });

    test('AuthAuthenticated on /auth/login bounces home', () {
      expect(
        computeAuthRedirect(
          auth: const AuthAuthenticated(),
          location: '/auth/login',
        ),
        '/',
      );
    });

    test('AuthAuthenticated on any non-auth route stays', () {
      expect(
        computeAuthRedirect(
          auth: const AuthAuthenticated(),
          location: '/orders/99',
        ),
        isNull,
      );
      expect(
        computeAuthRedirect(
          auth: const AuthAuthenticated(),
          location: '/checkout/payment',
        ),
        isNull,
      );
    });
  });

  group('computeAuthRedirect — auth routes accessible to guests', () {
    const authPublicRoutes = [
      '/auth/login',
      '/auth/register',
      '/auth/forgot-password',
      '/auth/verify-email',
      '/auth/mfa',
    ];

    for (final route in authPublicRoutes) {
      test('guest may reach $route directly', () {
        expect(
          computeAuthRedirect(
            auth: const AuthUnauthenticated(),
            location: route,
          ),
          isNull,
        );
      });
    }
  });

  group('computeSellerRedirect — /seller/* role gate', () {
    test('non-seller is redirected to / once role is known', () {
      expect(
        computeSellerRedirect(
          location: '/seller/dashboard',
          isSeller: false,
          sellerKnown: true,
        ),
        '/',
      );
    });

    test('seller passes through (null)', () {
      expect(
        computeSellerRedirect(
          location: '/seller/returns/123',
          isSeller: true,
          sellerKnown: true,
        ),
        isNull,
      );
    });

    test('deferred while role unknown (/me still loading)', () {
      expect(
        computeSellerRedirect(
          location: '/seller/dashboard',
          isSeller: false,
          sellerKnown: false,
        ),
        isNull,
      );
    });

    test('non-/seller routes are never gated', () {
      expect(
        computeSellerRedirect(
          location: '/account/profile',
          isSeller: false,
          sellerKnown: true,
        ),
        isNull,
      );
    });

    test('deep sub-route gated for non-seller', () {
      expect(
        computeSellerRedirect(
          location: '/seller/questions/456',
          isSeller: false,
          sellerKnown: true,
        ),
        '/',
      );
    });
  });
}
