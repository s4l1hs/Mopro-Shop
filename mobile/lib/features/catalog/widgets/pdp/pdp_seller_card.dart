import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Seller card for the PDP buy-box: store name + a "Mağazaya git" link.
///
/// The catalog `Product` exposes only `sellerName` (a string) today, not a
/// `Seller` object with a rating, so this takes the name directly. [onTap]
/// routes to the seller's store when provided. Extracted from the PDP so mobile
/// and desktop share one seller renderer.
class PdpSellerCard extends StatelessWidget {
  const PdpSellerCard({
    required this.sellerName,
    this.onTap,
    super.key,
  });

  final String sellerName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sellerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (onTap != null)
            TextButton(
              onPressed: onTap,
              child: Text('product.go_to_store'.tr()),
            ),
        ],
      ),
    );
  }
}
