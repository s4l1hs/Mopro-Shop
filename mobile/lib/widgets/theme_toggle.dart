import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/theme_controller.dart';

/// IconButton that cycles: system → light → dark → system.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeControllerProvider);

    final icon = switch (mode) {
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.system => Icons.brightness_auto,
    };

    return IconButton(
      icon: Icon(icon),
      tooltip: switch (mode) {
        ThemeMode.light => 'Açık tema',
        ThemeMode.dark => 'Koyu tema',
        ThemeMode.system => 'Sistem teması',
      },
      onPressed: () =>
          ref.read(themeControllerProvider.notifier).cycle(),
    );
  }
}
