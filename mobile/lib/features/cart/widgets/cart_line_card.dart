import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/shared/atoms/qty_stepper.dart';

class CartLineCard extends StatelessWidget {
  const CartLineCard({
    required this.line,
    required this.onRemove,
    required this.onDecrement,
    required this.onIncrement,
    super.key,
  });

  final CartLineDto line;
  final VoidCallback onRemove;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fmt = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    return Dismissible(
      key: ValueKey(line.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: colorScheme.errorContainer,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
            const SizedBox(height: 4),
            Text(
              'cart.remove_item'.tr(),
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) => onRemove(),
      child: Container(
        color: colorScheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              _CoverImage(
                url: line.coverImageUrl,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      line.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          fmt.format(line.priceMinor / 100.0),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          fmt.format(line.lineTotalMinor / 100.0),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              QtyStepper(
                qty: line.qty,
                onDecrement: onDecrement,
                onIncrement: onIncrement,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, required this.colorScheme});

  final String? url;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 28,
      ),
    );

    if (url == null || url!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}
