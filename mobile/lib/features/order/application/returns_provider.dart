import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/order/application/orders_provider.dart';
import 'package:mopro/features/order/data/return_dto.dart';

/// The authenticated user's returns ("İadelerim"). Shape #1: build() returns a
/// loading state and kicks off the fetch; state is only mutated afterwards.
final returnsProvider =
    NotifierProvider<ReturnsNotifier, AsyncValue<List<ReturnListItemDto>>>(
  ReturnsNotifier.new,
);

/// RT-06: the consumer's selected status filter on the return-history list.
/// `null` = all statuses. Pure client-side filter over the already-fetched
/// list — no extra fetch, no backend round-trip.
final returnsStatusFilterProvider = StateProvider<String?>((ref) => null);

class ReturnsNotifier extends Notifier<AsyncValue<List<ReturnListItemDto>>> {
  @override
  AsyncValue<List<ReturnListItemDto>> build() {
    _load();
    return const AsyncLoading();
  }

  Future<void> refresh() {
    state = const AsyncLoading();
    return _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(orderRepositoryProvider);
      state = AsyncData(await repo.listReturns());
    } on DioException catch (e, st) {
      final err = e.error;
      state = AsyncError(
        err is AppError ? err : NetworkError(message: e.message ?? ''),
        st,
      );
    } catch (e, st) {
      state = AsyncError(UnknownError(statusCode: 0, message: e.toString()), st);
    }
  }
}

/// Full return detail, keyed by return id.
final returnDetailProvider = NotifierProviderFamily<ReturnDetailNotifier,
    AsyncValue<ReturnDetailDto>, int>(ReturnDetailNotifier.new);

class ReturnDetailNotifier
    extends FamilyNotifier<AsyncValue<ReturnDetailDto>, int> {
  @override
  AsyncValue<ReturnDetailDto> build(int arg) {
    _load();
    return const AsyncLoading();
  }

  Future<void> refresh() {
    state = const AsyncLoading();
    return _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(orderRepositoryProvider);
      state = AsyncData(await repo.getReturn(arg));
    } on DioException catch (e, st) {
      final err = e.error;
      state = AsyncError(
        err is AppError ? err : NetworkError(message: e.message ?? ''),
        st,
      );
    } catch (e, st) {
      state = AsyncError(UnknownError(statusCode: 0, message: e.toString()), st);
    }
  }
}
