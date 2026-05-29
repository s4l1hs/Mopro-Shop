import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/widgets/theme_toggle.dart';

/// Thin desktop-only footer: copyright + placeholder info links + a language
/// menu + the theme toggle (delegating to the existing controllers). Copy is
/// placeholder via easy_localization keys.
class HomeFooter extends StatelessWidget {
  const HomeFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: CenteredContentColumn(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                '© 2026 Mopro',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(width: 16),
              const _FooterLink('footer.about'),
              const _FooterLink('footer.help'),
              const _FooterLink('footer.privacy'),
              const _FooterLink('footer.terms'),
              const _LanguageMenu(),
              const ThemeToggle(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink(this.labelKey);
  final String labelKey;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {}, // placeholder destinations (5b)
      child: Text(labelKey.tr()),
    );
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.language),
      tooltip: 'footer.language'.tr(),
      onSelected: (l) => context.setLocale(l),
      itemBuilder: (_) => [
        for (final l in context.supportedLocales)
          PopupMenuItem<Locale>(value: l, child: Text(l.languageCode.toUpperCase())),
      ],
    );
  }
}
