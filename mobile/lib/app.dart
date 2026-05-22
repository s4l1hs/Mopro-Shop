import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:mopro/core/theme/app_theme.dart';
import 'package:mopro/core/widgets/error_banner.dart';

class MoproApp extends ConsumerWidget {
  const MoproApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    ref.listen<bool>(sessionRevokedProvider, (_, revoked) {
      if (!revoked) return;
      // Reset immediately — banner is shown once via SnackBar.
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
    });

    return MaterialApp.router(
      title: 'Mopro',
      theme: AppTheme.light,
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}
