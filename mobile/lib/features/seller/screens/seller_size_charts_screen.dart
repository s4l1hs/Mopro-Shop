import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/seller/data/seller_size_chart_repository.dart';

/// `/seller/size-charts` — the seller's size-chart library. Tap a chart to edit,
/// or create a new one (optionally prefilled from the EN standard).
class SellerSizeChartsScreen extends ConsumerWidget {
  const SellerSizeChartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartsAsync = ref.watch(sellerSizeChartsProvider);
    return Scaffold(
      appBar: AppBar(title: Text('seller.charts_title'.tr())),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/seller/size-charts/new'),
        icon: const Icon(Icons.add),
        label: Text('seller.chart_new'.tr()),
      ),
      body: CenteredContentColumn(
        child: chartsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('seller.error_generic'.tr()),
            ),
          ),
          data: (charts) => charts.isEmpty
              ? _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: charts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ChartTile(chart: charts[i]),
                ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.straighten,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'seller.charts_empty'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartTile extends StatelessWidget {
  const _ChartTile({required this.chart});
  final SellerSizeChart chart;

  @override
  Widget build(BuildContext context) {
    final garment = 'seller.garment_${chart.garmentType}'.tr();
    final gender = 'fit.gender_${chart.gender}'.tr();
    return ListTile(
      leading: const Icon(Icons.straighten),
      title: Text(chart.name),
      subtitle: Text('$garment · $gender · ${chart.sizeSystem.toUpperCase()}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          context.push('/seller/size-charts/${chart.id}', extra: chart),
    );
  }
}
