import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Drop-in replacement for the promo card's 16:9 image when
/// `CachedNetworkImage` errors out. Keeps the panel's overall layout
/// stable (same dimensions, same corner radius, same border) so a
/// broken CDN URL never propagates a Flutter error frame into the
/// mega menu.
///
/// Visually: solid surface-variant background, centered icon, small
/// caption. Caption text is i18n-resolved via
/// `mega_menu.promo.image_unavailable`.
class PromoImagePlaceholder extends StatelessWidget {
  const PromoImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 40,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            'mega_menu.promo.image_unavailable'.tr(),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
