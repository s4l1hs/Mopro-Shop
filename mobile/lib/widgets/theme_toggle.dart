import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/theme_controller.dart';

/// IconButton that toggles light ↔ dark. The app no longer follows the OS, so
/// there is no system mode (the `system` arms below are unreachable but keep the
/// switches exhaustive over the [ThemeMode] enum).
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider);
    final isDark = mode == ThemeMode.dark;

    return IconButton(
      icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
      tooltip: isDark ? 'Koyu tema' : 'Açık tema',
      onPressed: () => ref.read(themeControllerProvider.notifier).cycle(),
    );
  }
}
