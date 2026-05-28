import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mopro/design/theme_controller.dart';

const _kGuestCartKey = 'mopro_guest_cart';

/// A single guest cart line item (pre-auth, stored locally).
class GuestCartItem {
  const GuestCartItem({
    required this.variantId,
    required this.productId,
    required this.qty,
  });

  final int variantId;
  final int productId;
  final int qty;

  Map<String, dynamic> toJson() => {
        'variant_id': variantId,
        'product_id': productId,
        'qty': qty,
      };

  factory GuestCartItem.fromJson(Map<String, dynamic> j) => GuestCartItem(
        variantId: j['variant_id'] as int,
        productId: j['product_id'] as int,
        qty: j['qty'] as int,
      );
}

class GuestCartNotifier extends StateNotifier<List<GuestCartItem>> {
  GuestCartNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        super(_load(prefs));

  final SharedPreferences _prefs;

  static List<GuestCartItem> _load(SharedPreferences p) {
    final raw = p.getString(_kGuestCartKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => GuestCartItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void addItem({required int variantId, required int productId, int qty = 1}) {
    final idx = state.indexWhere((i) => i.variantId == variantId);
    if (idx >= 0) {
      final updated = List<GuestCartItem>.from(state);
      updated[idx] = GuestCartItem(
        variantId: variantId,
        productId: productId,
        qty: updated[idx].qty + qty,
      );
      state = updated;
    } else {
      state = [
        ...state,
        GuestCartItem(variantId: variantId, productId: productId, qty: qty),
      ];
    }
    _save();
  }

  void removeItem(int variantId) {
    state = state.where((i) => i.variantId != variantId).toList();
    _save();
  }

  void updateQty(int variantId, int qty) {
    if (qty <= 0) {
      removeItem(variantId);
      return;
    }
    final idx = state.indexWhere((i) => i.variantId == variantId);
    if (idx < 0) return;
    final updated = List<GuestCartItem>.from(state);
    updated[idx] = GuestCartItem(
      variantId: variantId,
      productId: updated[idx].productId,
      qty: qty,
    );
    state = updated;
    _save();
  }

  void clear() {
    state = const [];
    _save();
  }

  int get itemCount => state.fold(0, (sum, i) => sum + i.qty);

  void _save() {
    _prefs.setString(
      _kGuestCartKey,
      jsonEncode(state.map((i) => i.toJson()).toList()),
    );
  }
}

final guestCartProvider =
    StateNotifierProvider<GuestCartNotifier, List<GuestCartItem>>((ref) {
  return GuestCartNotifier(ref.watch(sharedPreferencesProvider));
});

final guestCartCountProvider = Provider<int>((ref) {
  return ref.watch(guestCartProvider.notifier).itemCount;
});
