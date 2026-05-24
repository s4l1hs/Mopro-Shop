import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class ProductFilterOptions {
  const ProductFilterOptions({
    this.minPriceMinor,
    this.maxPriceMinor,
    this.freeShippingOnly = false,
    this.inStockOnly = false,
    this.cashbackOnly = false,
  });

  final int? minPriceMinor;
  final int? maxPriceMinor;
  final bool freeShippingOnly;
  final bool inStockOnly;
  final bool cashbackOnly;

  int get activeCount {
    var n = 0;
    if (minPriceMinor != null || maxPriceMinor != null) n++;
    if (freeShippingOnly) n++;
    if (inStockOnly) n++;
    if (cashbackOnly) n++;
    return n;
  }

  ProductFilterOptions copyWith({
    int? minPriceMinor,
    int? maxPriceMinor,
    bool? freeShippingOnly,
    bool? inStockOnly,
    bool? cashbackOnly,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
  }) {
    return ProductFilterOptions(
      minPriceMinor: clearMinPrice ? null : (minPriceMinor ?? this.minPriceMinor),
      maxPriceMinor: clearMaxPrice ? null : (maxPriceMinor ?? this.maxPriceMinor),
      freeShippingOnly: freeShippingOnly ?? this.freeShippingOnly,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      cashbackOnly: cashbackOnly ?? this.cashbackOnly,
    );
  }
}

Future<ProductFilterOptions?> showFilterSheet(
  BuildContext context, {
  ProductFilterOptions? current,
}) {
  return showModalBottomSheet<ProductFilterOptions>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => FilterSheet(current: current ?? const ProductFilterOptions()),
  );
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({required this.current, super.key});

  final ProductFilterOptions current;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late ProductFilterOptions _opts;
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _opts = widget.current;
    if (_opts.minPriceMinor != null) {
      _minController.text = (_opts.minPriceMinor! ~/ 100).toString();
    }
    if (_opts.maxPriceMinor != null) {
      _maxController.text = (_opts.maxPriceMinor! ~/ 100).toString();
    }
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'catalog.filter_title'.tr(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: _resetAll,
                    child: Text('catalog.filter_reset'.tr()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Text(
                    'catalog.filter_price_range'.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'catalog.filter_min_price'.tr(),
                            prefixText: '₺',
                          ),
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            setState(() {
                              _opts = _opts.copyWith(
                                minPriceMinor: n != null ? n * 100 : null,
                                clearMinPrice: n == null,
                              );
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'catalog.filter_max_price'.tr(),
                            prefixText: '₺',
                          ),
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            setState(() {
                              _opts = _opts.copyWith(
                                maxPriceMinor: n != null ? n * 100 : null,
                                clearMaxPrice: n == null,
                              );
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('catalog.filter_free_shipping'.tr()),
                    value: _opts.freeShippingOnly,
                    onChanged: (v) =>
                        setState(() => _opts = _opts.copyWith(freeShippingOnly: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('catalog.filter_in_stock'.tr()),
                    value: _opts.inStockOnly,
                    onChanged: (v) =>
                        setState(() => _opts = _opts.copyWith(inStockOnly: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('catalog.filter_cashback_only'.tr()),
                    value: _opts.cashbackOnly,
                    onChanged: (v) =>
                        setState(() => _opts = _opts.copyWith(cashbackOnly: v)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_opts),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text('catalog.filter_apply'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetAll() {
    setState(() {
      _opts = const ProductFilterOptions();
      _minController.clear();
      _maxController.clear();
    });
  }
}
