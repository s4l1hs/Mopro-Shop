import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';

/// Derived count of distinct line items — drives the badge on the Sepet tab.
final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).cart.valueOrNull?.lines.length ?? 0;
});
