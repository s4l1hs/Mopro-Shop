import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/seller/data/seller_size_chart_repository.dart';
import 'package:mopro/features/seller/data/seller_storefront_repository.dart';
import 'package:mopro/features/seller/user_is_seller_provider.dart';

const _garments = ['top', 'bottom', 'dress', 'skirt', 'outerwear'];
const _genders = ['female', 'male'];
const _systems = ['alpha', 'eu'];

/// Measurements required per garment type (EN 13402-2; mirrors the backend).
List<String> _requiredMeasurements(String garment) {
  switch (garment) {
    case 'top':
    case 'outerwear':
      return const ['chest'];
    case 'bottom':
    case 'skirt':
      return const ['waist', 'hip'];
    case 'dress':
      return const ['chest', 'waist', 'hip'];
  }
  return const ['chest'];
}

/// One editable size row: a label + min/max (mm) per measurement.
class _SizeRow {
  _SizeRow({String label = ''})
      : labelCtrl = TextEditingController(text: label);
  final TextEditingController labelCtrl;
  final Map<String, TextEditingController> minCtrl = {
    for (final m in ['chest', 'waist', 'hip']) m: TextEditingController(),
  };
  final Map<String, TextEditingController> maxCtrl = {
    for (final m in ['chest', 'waist', 'hip']) m: TextEditingController(),
  };

  void dispose() {
    labelCtrl.dispose();
    for (final c in minCtrl.values) {
      c.dispose();
    }
    for (final c in maxCtrl.values) {
      c.dispose();
    }
  }
}

/// `/seller/size-charts/new` and `/seller/size-charts/{id}` — create/edit a chart.
class SellerSizeChartEditorScreen extends ConsumerStatefulWidget {
  const SellerSizeChartEditorScreen({this.chart, super.key});
  final SellerSizeChart? chart;

  @override
  ConsumerState<SellerSizeChartEditorScreen> createState() =>
      _SellerSizeChartEditorScreenState();
}

class _SellerSizeChartEditorScreenState
    extends ConsumerState<SellerSizeChartEditorScreen> {
  late final TextEditingController _name;
  late String _garment;
  late String _gender;
  late String _system;
  final List<_SizeRow> _rows = [];
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.chart != null;

  @override
  void initState() {
    super.initState();
    final c = widget.chart;
    _name = TextEditingController(text: c?.name ?? '');
    _garment = c?.garmentType ?? 'top';
    _gender = c?.gender ?? 'female';
    _system = c?.sizeSystem ?? 'alpha';
    if (c != null) {
      _loadRows(c.rows);
    } else {
      _rows.add(_SizeRow());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Group flat rows by size label into editable _SizeRow entries.
  void _loadRows(List<SizeChartRow> rows) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    final byLabel = <String, _SizeRow>{};
    final order = <String>[];
    for (final row in rows) {
      final entry = byLabel.putIfAbsent(row.sizeLabel, () {
        order.add(row.sizeLabel);
        return _SizeRow(label: row.sizeLabel);
      });
      entry.minCtrl[row.measurement]?.text = '${row.minMm}';
      entry.maxCtrl[row.measurement]?.text = '${row.maxMm}';
    }
    for (final label in order) {
      _rows.add(byLabel[label]!);
    }
    if (_rows.isEmpty) _rows.add(_SizeRow());
  }

  Future<void> _copyFromStandard() async {
    setState(() => _error = null);
    final std = await ref
        .read(sellerSizeChartRepositoryProvider)
        .fetchStandard(garmentType: _garment, gender: _gender, sizeSystem: _system);
    if (!mounted) return;
    if (std == null || std.rows.isEmpty) {
      setState(() => _error = 'seller.chart_no_standard'.tr());
      return;
    }
    setState(() => _loadRows(std.rows));
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final required = _requiredMeasurements(_garment);
    final rows = <SizeChartRow>[];
    for (var i = 0; i < _rows.length; i++) {
      final e = _rows[i];
      final label = e.labelCtrl.text.trim();
      if (label.isEmpty) continue;
      for (final m in required) {
        final mn = int.tryParse(e.minCtrl[m]!.text.trim());
        final mx = int.tryParse(e.maxCtrl[m]!.text.trim());
        if (mn == null || mx == null) continue;
        rows.add(
          SizeChartRow(
            sizeLabel: label,
            sortRank: i + 1,
            measurement: m,
            minMm: mn,
            maxMm: mx,
          ),
        );
      }
    }
    final chart = SellerSizeChart(
      id: widget.chart?.id ?? 0,
      name: _name.text.trim(),
      garmentType: _garment,
      gender: _gender,
      sizeSystem: _system,
      source: 'seller',
      rows: rows,
    );
    final repo = ref.read(sellerSizeChartRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateChart(widget.chart!.id, chart);
      } else {
        await repo.createChart(chart);
      }
      ref.invalidate(sellerSizeChartsProvider);
      if (!mounted) return;
      context.pop();
    } on SizeChartValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'seller.chart_save_failed'.tr());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final required = _requiredMeasurements(_garment);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'seller.chart_edit'.tr() : 'seller.chart_new'.tr()),
      ),
      body: CenteredContentColumn(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: 'seller.chart_name'.tr()),
            ),
            const SizedBox(height: 12),
            _dropdown(
              'seller.chart_garment'.tr(), _garment, _garments,
              (v) => 'seller.garment_$v'.tr(),
              (v) => setState(() => _garment = v),
            ),
            const SizedBox(height: 8),
            _dropdown(
              'fit.gender_label'.tr(), _gender, _genders,
              (v) => 'fit.gender_$v'.tr(),
              (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 8),
            _dropdown(
              'seller.chart_system'.tr(), _system, _systems,
              (v) => v.toUpperCase(),
              (v) => setState(() => _system = v),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _copyFromStandard,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: Text('seller.chart_copy_standard'.tr()),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _rows.length; i++)
              _sizeCard(i, required),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_SizeRow())),
              icon: const Icon(Icons.add, size: 18),
              label: Text('seller.chart_add_size'.tr()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'fit.save'.tr() : 'seller.chart_save'.tr()),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openAttachDialog(widget.chart!.id),
                icon: const Icon(Icons.link, size: 18),
                label: Text('seller.chart_attach'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> items,
    String Function(String) display,
    ValueChanged<String> onChanged,
  ) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: [
            for (final it in items)
              DropdownMenuItem(value: it, child: Text(display(it))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _sizeCard(int i, List<String> measurements) {
    final e = _rows[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: e.labelCtrl,
                    decoration:
                        InputDecoration(labelText: 'seller.chart_size_label'.tr()),
                  ),
                ),
                IconButton(
                  tooltip: 'seller.chart_remove_size'.tr(),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _rows.length > 1
                      ? () => setState(() {
                            _rows.removeAt(i).dispose();
                          })
                      : null,
                ),
              ],
            ),
            for (final m in measurements)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(width: 64, child: Text('fit.$m'.tr())),
                    Expanded(child: _mmField(e.minCtrl[m]!, 'seller.chart_min'.tr())),
                    const SizedBox(width: 8),
                    Expanded(child: _mmField(e.maxCtrl[m]!, 'seller.chart_max'.tr())),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mmField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, suffixText: 'mm'),
      );

  Future<void> _openAttachDialog(int chartId) async {
    final slug = ref.read(currentSellerBindingProvider)?.sellerSlug;
    if (slug == null || slug.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _AttachProductDialog(slug: slug, chartId: chartId),
    );
  }
}

/// Picks one of the seller's products and attaches the chart to it.
class _AttachProductDialog extends ConsumerWidget {
  const _AttachProductDialog({required this.slug, required this.chartId});
  final String slug;
  final int chartId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text('seller.chart_attach_pick'.tr()),
      content: SizedBox(
        width: 360,
        child: FutureBuilder(
          future: ref
              .read(sellerStorefrontRepositoryProvider)
              .listProducts(slug, page: 1),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final (products, _) = snap.data!;
            if (products.isEmpty) {
              return Text('seller.chart_attach_no_products'.tr());
            }
            return SizedBox(
              height: 320,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in products)
                    ListTile(
                      title: Text(p.title),
                      onTap: () async {
                        await ref
                            .read(sellerSizeChartRepositoryProvider)
                            .attachToProduct(p.id, chartId);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('seller.chart_attached'.tr())),
                          );
                        }
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
      ],
    );
  }
}
