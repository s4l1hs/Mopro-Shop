import 'dart:async' show unawaited;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

// ── State

class WalletState {
  const WalletState({
    this.balance = const AsyncLoading(),
    this.transactions = const AsyncLoading(),
    this.loadingMore = false,
    this.loadMoreError,
    this.hasMore = false,
    this.nextCursor,
  });

  final AsyncValue<WalletBalance> balance;
  final AsyncValue<List<WalletTransaction>> transactions;
  final bool loadingMore;
  final AppError? loadMoreError;
  final bool hasMore;
  final String? nextCursor;

  WalletState copyWith({
    AsyncValue<WalletBalance>? balance,
    AsyncValue<List<WalletTransaction>>? transactions,
    bool? loadingMore,
    AppError? loadMoreError,
    bool clearLoadMoreError = false,
    bool? hasMore,
    String? nextCursor,
  }) =>
      WalletState(
        balance: balance ?? this.balance,
        transactions: transactions ?? this.transactions,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: clearLoadMoreError
            ? null
            : loadMoreError ?? this.loadMoreError,
        hasMore: hasMore ?? this.hasMore,
        nextCursor: nextCursor ?? this.nextCursor,
      );
}

// ── Provider

final walletProvider =
    NotifierProvider<WalletNotifier, WalletState>(WalletNotifier.new);

// ── Notifier

class WalletNotifier extends Notifier<WalletState> {
  @override
  WalletState build() {
    unawaited(_init());
    return const WalletState();
  }

  Future<void> refresh() async {
    await Future.wait([_loadBalance(), _loadTransactions(null)]);
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    final cursor = state.nextCursor;
    if (cursor == null) return;
    state = state.copyWith(
      loadingMore: true,
      clearLoadMoreError: true,
    );
    await _loadTransactions(cursor);
  }

  Future<void> _init() async {
    await Future.wait([_loadBalance(), _loadTransactions(null)]);
  }

  Future<void> _loadBalance() async {
    try {
      final api = ref.read(walletApiProvider);
      final resp = await api.getWalletBalance();
      state = state.copyWith(balance: AsyncData(resp.data!));
    } on DioException catch (e, st) {
      final err = e.error;
      state = state.copyWith(
        balance: AsyncError(
          err is AppError
              ? err
              : NetworkError(message: e.message ?? ''),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(
        balance: AsyncError(
          UnknownError(statusCode: 0, message: e.toString()),
          st,
        ),
      );
    }
  }

  Future<void> _loadTransactions(String? cursor) async {
    try {
      final api = ref.read(walletApiProvider);
      final resp = await api.listWalletTransactions(
        cursor: cursor,
        limit: 20,
      );
      final data = resp.data!;
      final incoming = data.data;
      final existing = cursor == null
          ? <WalletTransaction>[]
          : state.transactions.valueOrNull ??
              <WalletTransaction>[];
      state = state.copyWith(
        transactions: AsyncData([...existing, ...incoming]),
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
          transactions: AsyncError(appError, st),
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
        state = state.copyWith(
          transactions: AsyncError(appError, st),
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
