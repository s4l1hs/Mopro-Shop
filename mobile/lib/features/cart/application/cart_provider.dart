
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/cart/application/cart_cashback_cache.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/cart/data/cart_repository_impl.dart';

// ── Derived providers ─────────────────────────────────────────────────────────

/// Total monthly cashback (in minor units) across all cart lines.
/// Reads from the local cashback cache (populated at "Add to Cart" time).
final cartMonthlyCashbackProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final cart = ref.watch(cartProvider).cart.valueOrNull;
  if (cart == null || cart.isEmpty) return 0;
  final cache = ref.read(cartCashbackCacheProvider);
  final all = await cache.getAll();
  var total = 0;
  for (final line in cart.lines) {
    final monthly = all[line.variantId] ?? 0;
    total += monthly * line.qty;
  }
  return total;
});

// ── Repository provider ───────────────────────────────────────────────────────

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return CartRepositoryImpl(ref.watch(dioProvider));
});

// ── State ─────────────────────────────────────────────────────────────────────

class CartState {
  const CartState({
    this.cart = const AsyncLoading(),
    this.isMutating = false,
  });

  final AsyncValue<CartDto> cart;
  final bool isMutating;

  CartState copyWith({
    AsyncValue<CartDto>? cart,
    bool? isMutating,
  }) =>
      CartState(
        cart: cart ?? this.cart,
        isMutating: isMutating ?? this.isMutating,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

final cartProvider =
    NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

// ── Notifier ──────────────────────────────────────────────────────────────────

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    // Defer to microtask so build() returns and notifier is initialised
    // before _load tries to write to state.
    Future<void>.microtask(_load);
    return const CartState();
  }

  Future<void> refresh() => _load();

  Future<void> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async {
    state = state.copyWith(isMutating: true);
    try {
      final repo = ref.read(cartRepositoryProvider);
      final cart = await repo.addItem(
        productId: productId,
        variantId: variantId,
        qty: qty,
      );
      state = state.copyWith(cart: AsyncData(cart), isMutating: false);
    } catch (_) {
      state = state.copyWith(isMutating: false);
      rethrow;
    }
  }

  Future<void> updateQty({
    required String lineId,
    required int qty,
  }) async {
    state = state.copyWith(isMutating: true);
    try {
      final repo = ref.read(cartRepositoryProvider);
      final cart = await repo.updateQty(lineId: lineId, qty: qty);
      state = state.copyWith(cart: AsyncData(cart), isMutating: false);
    } catch (_) {
      state = state.copyWith(isMutating: false);
      rethrow;
    }
  }

  Future<void> removeLine({required String lineId}) async {
    state = state.copyWith(isMutating: true);
    try {
      final repo = ref.read(cartRepositoryProvider);
      await repo.removeLine(lineId: lineId);
      await _load();
    } catch (_) {
      state = state.copyWith(isMutating: false);
      rethrow;
    }
  }

  Future<void> clear() async {
    state = state.copyWith(isMutating: true);
    try {
      final repo = ref.read(cartRepositoryProvider);
      await repo.clear();
      state = state.copyWith(
        cart: AsyncData(CartDto.empty()),
        isMutating: false,
      );
    } catch (_) {
      state = state.copyWith(isMutating: false);
      rethrow;
    }
  }

  Future<void> _load() async {
    state = state.copyWith(cart: const AsyncLoading());
    try {
      final repo = ref.read(cartRepositoryProvider);
      final cart = await repo.getCart();
      state = state.copyWith(cart: AsyncData(cart));
    } on DioException catch (e, st) {
      final err = e.error;
      state = state.copyWith(
        cart: AsyncError(
          err is AppError
              ? err
              : NetworkError(message: e.message ?? ''),
          st,
        ),
      );
    } catch (e, st) {
      state = state.copyWith(
        cart: AsyncError(
          UnknownError(statusCode: 0, message: e.toString()),
          st,
        ),
      );
    }
  }
}
