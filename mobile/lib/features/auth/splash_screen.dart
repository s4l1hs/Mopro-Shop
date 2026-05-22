import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Give auth check a maximum of 3 seconds before forcing unauthenticated.
    final result = await ref
        .read(authNotifierProvider.future)
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => const AuthUnauthenticated(),
        );

    if (!mounted) return;

    switch (result) {
      case AuthAuthenticated():
        context.go('/');
      case AuthProfileIncomplete():
        context.go('/auth/profile');
      case AuthUnauthenticated():
        context.go('/auth/phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator.adaptive(),
      ),
    );
  }
}
