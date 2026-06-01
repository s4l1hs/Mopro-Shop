import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';

/// Overview counters for the seller dashboard. "Approved this month" is omitted
/// — the 5a /seller/returns endpoint has no date filter (Backlog).
class SellerDashboardSummary {
  const SellerDashboardSummary({
    required this.pendingReturns,
    required this.pendingReturnsHasMore,
    required this.unansweredQuestions,
  });

  final int pendingReturns;
  final bool pendingReturnsHasMore;
  final int unansweredQuestions;

  bool get allClear => pendingReturns == 0 && unansweredQuestions == 0;
}

/// Fetches the dashboard counters in parallel. autoDispose so it refetches on
/// re-entry; refresh via ref.invalidate.
final sellerDashboardSummaryProvider =
    FutureProvider.autoDispose<SellerDashboardSummary>((ref) async {
  final repo = ref.watch(sellerRepositoryProvider);
  // Returns has no total → count the first page + hasMore flag.
  final returnsFut = repo.listReturns(status: 'submitted');
  final questionsFut = repo.listQuestions(unanswered: true, pageSize: 1);
  final (returns, qResult) = (await returnsFut, await questionsFut);
  final (returnItems, returnsHasMore) = returns;
  final (_, unansweredTotal, _) = qResult;
  return SellerDashboardSummary(
    pendingReturns: returnItems.length,
    pendingReturnsHasMore: returnsHasMore,
    unansweredQuestions: unansweredTotal,
  );
});
