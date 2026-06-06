import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro_api/mopro_api.dart';

/// Pre-purchase delivery estimate for the PDP buy-box (P-034 / Trendyol parity:
/// "2-3 iş gününde kargoda"). Driven by the catalog API's [DeliveryEta], which is
/// a cheap table-driven estimate — never a carrier call or an SLA.
///
/// A [DeliveryEta.confident] estimate (concrete origin×destination) reads as a
/// firm "{min}-{max} iş gününde kargoda"; a fallback estimate (unknown origin or
/// a guest with no address) is hedged as "Tahmini {min}-{max} iş günü" so the UI
/// never promises a number it did not compute. The widget renders nothing when
/// `eta` is null — the screen omits it.
class PdpDeliveryInfo extends StatelessWidget {
  const PdpDeliveryInfo({required this.eta, super.key});

  final DeliveryEta eta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final args = <String, String>{
      'min': eta.minDays.toString(),
      'max': eta.maxDays.toString(),
    };
    final headline = eta.confident
        ? 'product.delivery_eta_confident'.tr(namedArgs: args)
        : 'product.delivery_eta_estimate'.tr(namedArgs: args);

    final city = eta.dispatchCity;
    final fromLine = (city != null && city.isNotEmpty)
        ? 'product.delivery_eta_from'.tr(namedArgs: {'city': _capitalize(city)})
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.local_shipping_outlined, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: eta.confident ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              if (fromLine != null) ...[
                const SizedBox(height: 2),
                Text(
                  fromLine,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // The dispatch city arrives as a normalized ASCII key (e.g. "istanbul");
  // capitalize the first letter for display.
  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
