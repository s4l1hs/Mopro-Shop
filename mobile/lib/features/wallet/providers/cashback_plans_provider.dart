import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

// ── State

class CashbackPlansState {
  const CashbackPlansState({
    this.plans = const AsyncLoading(),
    this.loadingMore = false,
    this.loadMoreError,
    this.hasMore = false,
    this.nextCursor,
  });

  final AsyncValue<List<CashbackPlan>> plans;
  final bool loadingMore;
  final AppError? loadMoreError;
  final bool hasMore;
  final String? nextCursor;

  CashbackPlansState copyWith({
    AsyncValue<List<CashbackPlan>>? plans,
    bool? loadingMore,
    AppError? loadMoreError,
    bool clearLoadMoreError = false,
    bool? hasMore,
    String? nextCursor,
  }) =>
      CashbackPlansState(
        plans: plans ?? this.plans,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: clearLoadMoreError
            ? null
            : loadMoreError ?? this.loadMoreError,
        hasMore: hasMore ?? this.hasMore,
        nextCursor: nextCursor ?? this.nextCursor,
      );
}

// ── Provider

final cashbackPlansProvider =
    NotifierProvider<CashbackPlansNotifier, CashbackPlansState>(
  CashbackPlansNotifier.new,
);

// ── Notifier

class CashbackPlansNotifier extends Notifier<CashbackPlansState> {
  @override
  CashbackPlansState build() {
    unawaited(_load(null));
    return const CashbackPlansState();
  }

  Future<void> refresh() => _load(null);

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;
    state = state.copyWith(
      loadingMore: true,
      clearLoadMoreError: true,
    );
    await _load(cursor);
  }

  Future<void> _load(String? cursor) async {
    try {
      final api = ref.read(cashbackApiProvider);
      final resp = await api.listCashbackPlans(
        cursor: cursor,
      );
      final data = resp.data!;
      final incoming = data.data;
      final existing = cursor == null
          ? <CashbackPlan>[]
          : state.plans.valueOrNull ?? <CashbackPlan>[];
      state = state.copyWith(
        plans: AsyncData([...existing, ...incoming]),
        hasMore: data.pagination.hasMore,
        nextCursor: data.pagination.nextCursor,
        loadingMore: false,
        clearLoadMoreError: true,
      );
    } on DioException catch (e, st) {
      final err = e.error;
      final appError = err is AppError
          ? err
          : NetworkError(message: e.message ?? '');
      if (cursor == null) {
        state = state.copyWith(
          plans: AsyncError(appError, st),
        );
      } else {
        state = state.copyWith(
          loadMoreError: appError,
          loadingMore: false,
        );
      }
    } catch (e, st) {
      final appError = UnknownError(
        statusCode: 0,
        message: e.toString(),
      );
      if (cursor == null) {
        state = state.copyWith(plans: AsyncError(appError, st));
      } else {
        state = state.copyWith(
          loadMoreError: appError,
          loadingMore: false,
        );
      }
    }
  }
}
