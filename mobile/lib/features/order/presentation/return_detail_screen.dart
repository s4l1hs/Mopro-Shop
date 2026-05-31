import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/order/application/returns_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/data/return_dto.dart';
import 'package:mopro/features/order/widgets/order_status_chip.dart';
import 'package:mopro/features/order/widgets/refund_status_card.dart';

class ReturnDetailScreen extends ConsumerWidget {
  const ReturnDetailScreen({required this.returnId, super.key});

  final int returnId;

  /// Maps a return lifecycle status to the timeline's post-purchase state.
  static String timelineStatus(String lifecycle) => switch (lifecycle) {
        ReturnLifecycle.approved => OrderStatus.returnApproved,
        ReturnLifecycle.rejected => OrderStatus.returnRejected,
        ReturnLifecycle.refunded => OrderStatus.refundIssued,
        _ => OrderStatus.returnRequested,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(returnDetailProvider(returnId));
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(
              title: Text(
                'returns.detail_title'.tr(args: ['$returnId']),
              ),
            ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final appError = err is AppError
              ? err
              : UnknownError(statusCode: 0, message: err.toString());
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () =>
                  ref.read(returnDetailProvider(returnId).notifier).refresh(),
            ),
          );
        },
        data: (ret) => _Body(ret: ret),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.ret});

  final ReturnDetailDto ret;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'returns.detail_title'.tr(args: ['${ret.id}']),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        OrderStatusTimeline(
          status: ReturnDetailScreen.timelineStatus(ret.status),
          at: ret.createdAt,
        ),
        const SizedBox(height: 24),
        Text('returns.review_title'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          ReturnReason.label(ret.reason),
          style: theme.textTheme.bodyMedium,
        ),
        if (ret.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            ret.description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'returns.items_count'.tr(args: ['${ret.items.length}']),
          style: theme.textTheme.bodyMedium,
        ),
        if (ret.refund != null) ...[
          const SizedBox(height: 24),
          RefundStatusCard(refund: ret.refund!),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => context.go('/orders/${ret.orderId}'),
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text('returns.original_order'.tr()),
        ),
      ],
    );
  }
}
