import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed cache mapping variantId → cashbackMonthlyMinor.
///
/// The server cart DTO does not carry cashback amounts; this local cache is
/// populated when the user taps "Add to Cart" from PDP (where the
/// cashbackPreview is available).
class CartCashbackCache {
  static const _key = 'mopro_cart_cashback_v1';

  Future<void> store(int variantId, int monthlyMinor) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final map = raw != null
        ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
        : <String, dynamic>{};
    map['$variantId'] = monthlyMinor;
    await prefs.setString(_key, jsonEncode(map));
  }

  Future<int?> get(int variantId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final v = map['$variantId'];
    if (v is num) return v.toInt();
    return null;
  }

  Future<Map<int, int>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return {
      for (final e in map.entries)
        if (int.tryParse(e.key) != null && e.value is num)
          int.parse(e.key): (e.value as num).toInt(),
    };
  }

  Future<void> remove(int variantId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    map.remove('$variantId');
    await prefs.setString(_key, jsonEncode(map));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final cartCashbackCacheProvider = Provider<CartCashbackCache>(
  (_) => CartCashbackCache(),
);
