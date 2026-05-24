import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/order_dto.dart';
import 'package:mopro/features/order/widgets/order_summary_card.dart';

enum _OrderFilter { all, active, completed, cancelled }

class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  _OrderFilter _filter = _OrderFilter.all;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesFilter(OrderDto order) {
    return switch (_filter) {
      _OrderFilter.all => true,
      _OrderFilter.active =>
        order.status != OrderStatus.delivered &&
            order.status != OrderStatus.cancelled &&
            order.status != OrderStatus.refunded,
      _OrderFilter.completed => order.status == OrderStatus.delivered,
      _OrderFilter.cancelled =>
        order.status == OrderStatus.cancelled ||
            order.status == OrderStatus.refunded,
    };
  }

  bool _matchesQuery(OrderDto order) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if ('${order.id}'.contains(q)) return true;
    return order.items.any(
      (i) => i.title.toLowerCase().contains(q),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('order.history_title'.tr()),
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'order.search_hint'.tr(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // ── Filter chips ──────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: _OrderFilter.values.map((f) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_filterLabel(f)),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                );
              }).toList(),
            ),
          ),
          // ── List ──────────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(ordersProvider.notifier).refresh(),
              child: state.orders.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) {
                  final appError = err is AppError
                      ? err
                      : UnknownError(
                          statusCode: 0,
                          message: err.toString(),
                        );
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
                  final filtered = orders
                      .where(_matchesFilter)
                      .where(_matchesQuery)
                      .toList();

                  if (filtered.isEmpty) {
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
                      itemCount: filtered.length +
                          (state.loadingMore || state.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i == filtered.length) {
                          if (state.loadingMore) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child:
                                  Center(child: CircularProgressIndicator()),
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
                        return OrderSummaryCard(order: filtered[i]);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(_OrderFilter f) => switch (f) {
        _OrderFilter.all => 'order.filter_all'.tr(),
        _OrderFilter.active => 'order.filter_active'.tr(),
        _OrderFilter.completed => 'order.filter_completed'.tr(),
        _OrderFilter.cancelled => 'order.filter_cancelled'.tr(),
      };
}
