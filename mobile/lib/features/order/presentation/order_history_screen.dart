import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/widgets/order_summary_card.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('order.history_title'.tr()),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
        child: state.orders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) {
            final appError = err is AppError
                ? err
                : UnknownError(statusCode: 0, message: err.toString());
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(
                    error: appError,
                    onRetry: () =>
                        ref.read(ordersProvider.notifier).refresh(),
                  ),
                ),
              ],
            );
          },
          data: (orders) {
            if (orders.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [EmptyState.empty()],
              );
            }

            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    notification.metrics.pixels >=
                        notification.metrics.maxScrollExtent - 200) {
                  ref.read(ordersProvider.notifier).loadNextPage();
                }
                return false;
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: orders.length +
                    (state.loadingMore || state.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == orders.length) {
                    if (state.loadingMore) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (state.loadMoreError != null) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: ErrorBanner(
                          error: state.loadMoreError!,
                          onRetry: () => ref
                              .read(ordersProvider.notifier)
                              .loadNextPage(),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                  return OrderSummaryCard(order: orders[i]);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
