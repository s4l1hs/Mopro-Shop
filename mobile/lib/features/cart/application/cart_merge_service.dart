import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/cart/application/guest_cart_provider.dart';

/// Merges guest cart into server cart after login.
/// Call this once after auth state transitions to Authenticated.
Future<void> mergeGuestCart(Ref ref) async {
  final guestItems = ref.read(guestCartProvider);
  if (guestItems.isEmpty) return;

  final dio = ref.read(dioProvider);
  try {
    await dio.post<void>('/cart/merge', data: {
      'items': guestItems
          .map((i) => {'variant_id': i.variantId, 'qty': i.qty})
          .toList(),
    });
    // Clear guest cart after successful merge.
    ref.read(guestCartProvider.notifier).clear();
  } on DioException catch (e) {
    // Non-fatal — server cart is the source of truth after login.
    // Log and continue; guest items will remain locally until next merge attempt.
    // ignore: avoid_print
    print('cart merge failed: ${e.message}');
  }
}

/// Merges guest favorites into server favorites after login.
Future<void> mergeGuestFavorites(Ref ref, Set<int> guestFavIds) async {
  if (guestFavIds.isEmpty) return;
  final dio = ref.read(dioProvider);
  try {
    await dio.post<void>(
      '/favorites/sync',
      data: {'product_ids': guestFavIds.toList()},
    );
  } on DioException catch (_) {
    // Non-fatal — local favorites remain as fallback.
  }
}
