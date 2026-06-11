import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/order/data/order_dto.dart';

/// Read-only delivery-address card on the order detail (OR-02). Renders the frozen
/// ship-to snapshot captured at checkout. Hidden when the order has no snapshot
/// (legacy orders predating address capture).
class DeliveryAddressCard extends StatelessWidget {
  const DeliveryAddressCard({required this.address, super.key});

  final DeliveryAddressDto address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locality = address.localityLine;

    return Semantics(
      container: true,
      label: 'order.delivery_address_title'.tr(),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'order.delivery_address_title'.tr(),
                  style: theme.textTheme.titleSmall,
                ),
                if (address.label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      address.label,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (address.recipientName.isNotEmpty)
              Text(
                address.recipientName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            if (address.fullAddress.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                address.fullAddress,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (locality.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                locality,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (address.phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                address.phone,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
