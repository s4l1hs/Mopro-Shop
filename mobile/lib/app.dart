import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/analytics/analytics_service.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';

class MoproApp extends ConsumerWidget {
  const MoproApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeControllerProvider);

    // Merge-on-auth (Tranche 4c): when the user transitions to authenticated,
    // link the persisted guest session so the backend backfills recently-viewed,
    // then refresh the rail. Best-effort — never blocks or breaks login.
    ref
      ..listen<AsyncValue<AuthState>>(authNotifierProvider, (prev, next) {
        final was = prev?.valueOrNull is AuthAuthenticated;
        final now = next.valueOrNull is AuthAuthenticated;
        if (!was && now) {
          Future<void>(() async {
            try {
              await ref.read(analyticsServiceProvider).identify();
            } catch (_) {/* identify failure must not affect login */}
            ref.invalidate(recentlyViewedProvider);
          });
        }
      })
      ..listen<bool>(sessionRevokedProvider, (_, revoked) {
      if (!revoked) return;
      ref.read(sessionRevokedProvider.notifier).state = false;

      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: ErrorBanner(error: SessionRevokedError()),
          duration: Duration(seconds: 6),
        ),
      );
    })
      // One-shot snackbar from a redirect (e.g. seller role-gate denial).
      ..listen<String?>(pendingSnackbarProvider, (_, key) {
        if (key == null) return;
        ref.read(pendingSnackbarProvider.notifier).state = null;
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text(key.tr())),
        );
      });

    return MaterialApp.router(
      title: 'Mopro',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      // Desktop-web fluidity: let mouse + trackpad drag-scroll the custom grids,
      // FilterPanel rails, and horizontal carousels (wheel already works; the
      // default web behaviour omits pointer-drag for mouse/trackpad).
      scrollBehavior: const _AppScrollBehavior(),
      // Layout safety: honour user text scaling but cap it at 1.3× so extreme
      // accessibility sizes can't overflow tight cells (320 dp ProductCard,
      // price blocks, bottom nav) into RenderFlex errors. Scaling down is
      // unclamped.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: child!,
        );
      },
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}

/// App-wide scroll behaviour. Adds mouse + trackpad (and keeps touch/stylus) to
/// the set of devices that can drag-scroll, so the Flutter Web storefront feels
/// native to desktop pointers across the multi-column grids and side rails.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
