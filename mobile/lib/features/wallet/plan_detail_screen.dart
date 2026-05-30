import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/coin_formatter.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/wallet/providers/plan_detail_provider.dart';
import 'package:mopro/features/wallet/widgets/plan_timeline_row.dart';
import 'package:mopro_api/mopro_api.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({required this.planId, super.key});

  final int planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(planDetailProvider(planId));

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(
              title: state.plan.maybeWhen(
          data: (plan) => Text(
            plan.productTitle,
            overflow: TextOverflow.ellipsis,
          ),
          orElse: () => Text('cashback.plan_detail_title'.tr()),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(planDetailProvider(planId).notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ..._planHeaderSlivers(context, state),
            ..._paymentsSlivers(context, ref, state),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _planHeaderSlivers(
    BuildContext context,
    PlanDetailState state,
  ) {
    if (state.plan.isLoading) {
      return [
        const SliverToBoxAdapter(child: _LoadingSpinner()),
      ];
    }
    if (state.plan.hasError) {
      final err = state.plan.error;
      final appError = err is AppError
          ? err
          : UnknownError(statusCode: 0, message: err.toString());
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(error: appError),
          ),
        ),
      ];
    }
    final plan = state.plan.valueOrNull;
    if (plan == null) return [];
    return [
      SliverToBoxAdapter(
        child: _PlanHeader(plan: plan),
      ),
      const SliverToBoxAdapter(
        child: _PerpetualNote(),
      ),
    ];
  }

  List<Widget> _paymentsSlivers(
    BuildContext context,
    WidgetRef ref,
    PlanDetailState state,
  ) {
    final currency = state.plan.valueOrNull?.currency ?? 'TRY_COIN';
    final header = SliverToBoxAdapter(
      child: _SectionHeader(
        title: 'cashback.payment_history_title'.tr(),
      ),
    );

    if (state.payments.isLoading) {
      return [
        header,
        const SliverToBoxAdapter(child: _LoadingSpinner()),
      ];
    }
    if (state.payments.hasError) {
      final err = state.payments.error;
      final appError = err is AppError
          ? err
          : UnknownError(statusCode: 0, message: err.toString());
      return [
        header,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () =>
                  ref.read(planDetailProvider(planId).notifier).refresh(),
            ),
          ),
        ),
      ];
    }
    final payments = state.payments.valueOrNull ?? [];
    if (payments.isEmpty) {
      return [
        header,
        const SliverToBoxAdapter(
          child: _EmptyPayments(),
        ),
      ];
    }
    return [
      header,
      SliverList.builder(
        itemCount: payments.length,
        itemBuilder: (_, i) => PlanTimelineRow(
          payment: payments[i],
          currency: currency,
        ),
      ),
      if (state.hasMore)
        SliverToBoxAdapter(
          child: _LoadMoreButton(
            loading: state.loadingMore,
            onPressed: () => ref
                .read(planDetailProvider(planId).notifier)
                .loadMorePayments(),
          ),
        ),
      if (state.loadMoreError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: state.loadMoreError!,
              onRetry: () => ref
                  .read(planDetailProvider(planId).notifier)
                  .loadMorePayments(),
            ),
          ),
        ),
    ];
  }
}

// ── Private helpers

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.plan});

  final CashbackPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _ProductImage(imageUrl: plan.productImageUrl),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.productTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  formatCoin(
                    plan.monthlyAmountMinor,
                    plan.currency,
                    compact: false,
                  ),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'cashback.perpetual_label'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imageUrl!,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _placeholder(colorScheme),
        ),
      );
    }
    return _placeholder(colorScheme);
  }

  Widget _placeholder(ColorScheme colorScheme) => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.shopping_bag_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 32,
        ),
      );
}

class _PerpetualNote extends StatelessWidget {
  const _PerpetualNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'cashback.perpetual_note'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color:
                    Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}

class _EmptyPayments extends StatelessWidget {
  const _EmptyPayments();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 40,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'cashback.no_payments'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  child:
                      Text('cashback.load_more_payments'.tr()),
                ),
        ),
      );
}
