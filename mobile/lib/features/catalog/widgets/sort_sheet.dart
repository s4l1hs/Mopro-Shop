import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const _sortOptions = [
  ('recommended', 'catalog.sort_recommended'),
  ('bestseller', 'catalog.sort_bestseller'),
  ('newest', 'catalog.sort_newest'),
  ('price_asc', 'catalog.sort_price_asc'),
  ('price_desc', 'catalog.sort_price_desc'),
  ('cashback_desc', 'catalog.sort_cashback_desc'),
];

Future<String?> showSortSheet(
  BuildContext context, {
  String current = 'recommended',
}) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SortSheet(current: current),
  );
}

class SortSheet extends StatelessWidget {
  const SortSheet({required this.current, super.key});

  final String current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'catalog.sort_title'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // All sort options render — `bestseller` is backed by real popularity
          // server-side (P-029: in-process global popularity, PR #90).
          ..._sortOptions.map(
            // TODO(4e): migrate to RadioGroup (Radio API deprecated Flutter 3.32)
            (opt) => RadioListTile<String>(
              title: Text(opt.$2.tr()),
              value: opt.$1,
              groupValue: current, // ignore: deprecated_member_use
              onChanged: (v) => // ignore: deprecated_member_use
                  Navigator.of(context).pop(v),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
