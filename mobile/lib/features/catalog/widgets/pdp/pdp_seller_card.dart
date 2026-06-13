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
    this.isOfficial = false,
    this.ratingAvg,
    this.ratingCount = 0,
    this.onTap,
    super.key,
  });

  final String sellerName;

  /// When true, renders the "Resmi Satıcı" official/verified-seller check next
  /// to the store name (PD-04).
  final bool isOfficial;

  /// PD-04: the seller's aggregate review rating. A star + average + review count
  /// row renders only when [ratingCount] > 0 (empty state = no rating shown).
  final double? ratingAvg;
  final int ratingCount;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        sellerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (isOfficial) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'product.official_seller'.tr(),
                        child: const Icon(
                          Icons.verified,
                          size: 16,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ],
                ),
                // PD-04: seller rating row — only when the seller has reviews.
                if (ratingCount > 0 && ratingAvg != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
                      const SizedBox(width: 2),
                      Text(
                        ratingAvg!.toStringAsFixed(1),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'product.review_count'
                              .tr(namedArgs: {'count': '$ratingCount'}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            Semantics(
              button: true,
              label: 'product.go_to_store_a11y'.tr(),
              child: TextButton(
                onPressed: onTap,
                child: Text('product.go_to_store'.tr()),
              ),
            ),
        ],
      ),
    );
  }
}
