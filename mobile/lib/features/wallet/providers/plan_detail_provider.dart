import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

// ── State

class PlanDetailState {
  const PlanDetailState({
    this.plan = const AsyncLoading(),
    this.payments = const AsyncLoading(),
    this.loadingMore = false,
    this.loadMoreError,
    this.hasMore = false,
    this.nextCursor,
  });

  final AsyncValue<CashbackPlan> plan;
  final AsyncValue<List<CashbackPayment>> payments;
  final bool loadingMore;
  final AppError? loadMoreError;
  final bool hasMore;
  final String? nextCursor;

  PlanDetailState copyWith({
    AsyncValue<CashbackPlan>? plan,
    AsyncValue<List<CashbackPayment>>? payments,
    bool? loadingMore,
    AppError? loadMoreError,
    bool clearLoadMoreError = false,
    bool? hasMore,
    String? nextCursor,
  }) =>
      PlanDetailState(
        plan: plan ?? this.plan,
        payments: payments ?? this.payments,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: clearLoadMoreError
            ? null
            : loadMoreError ?? this.loadMoreError,
        hasMore: hasMore ?? this.hasMore,
        nextCursor: nextCursor ?? this.nextCursor,
      );
}

// ── Provider

final planDetailProvider = AutoDisposeNotifierProviderFamily<
    PlanDetailNotifier, PlanDetailState, int>(
  PlanDetailNotifier.new,
);

// ── Notifier

class PlanDetailNotifier
    extends AutoDisposeFamilyNotifier<PlanDetailState, int> {
  @override
  PlanDetailState build(int arg) {
    unawaited(_init(arg));
    return const PlanDetailState();
  }

  Future<void> refresh() => _init(arg);

  Future<void> loadMorePayments() async {
    if (state.loadingMore || !state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;
    state = state.copyWith(
      loadingMore: true,
      clearLoadMoreError: true,
    );
    await _loadPayments(arg, cursor);
  }

  Future<void> _init(int planId) async {
    await Future.wait([
      _loadPlan(planId),
      _loadPayments(planId, null),
    ]);
  }

  Future<void> _loadPlan(int planId) async {
    try {
      final api = ref.read(cashbackApiProvider);
      final resp = await api.getCashbackPlan(id: planId);
      state = state.copyWith(plan: AsyncData(resp.data!));
    } on DioException catch (e, st) {
      final err = e.error;
      state = state.copyWith(
        plan: AsyncError(
          err is AppError
              ? err
              : NetworkError(message: e.message ?? ''),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(
        plan: AsyncError(
          UnknownError(statusCode: 0, message: e.toString()),
          st,
        ),
      );
    }
  }

  Future<void> _loadPayments(int planId, String? cursor) async {
    try {
      final api = ref.read(cashbackApiProvider);
      final resp = await api.listCashbackPayments(
        id: planId,
        cursor: cursor,
      );
      final data = resp.data!;
      final incoming = data.data;
      final existing = cursor == null
          ? <CashbackPayment>[]
          : state.payments.valueOrNull ?? <CashbackPayment>[];
      state = state.copyWith(
        payments: AsyncData([...existing, ...incoming]),
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
          payments: AsyncError(appError, st),
        );
      } else {
        state = state.copyWith(
          loadMoreError: appError,
          loadingMore: false,
        );
      }
    } catch (e, st) {
      final appError =
          UnknownError(statusCode: 0, message: e.toString());
      if (cursor == null) {
        state = state.copyWith(
          payments: AsyncError(appError, st),
        );
      } else {
        state = state.copyWith(
          loadMoreError: appError,
          loadingMore: false,
        );
      }
    }
  }
}
