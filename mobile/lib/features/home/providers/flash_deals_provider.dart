import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro_api/mopro_api.dart';

/// Active flash-deals collection for the home rail.
class FlashDealsCollection {
  const FlashDealsCollection({
    required this.id,
    required this.title,
    required this.endsAt,
    required this.products,
  });

  final int id;
  final String title;
  final DateTime endsAt;
  final List<ProductSummary> products;
}

/// Fetches `GET /home/flash-deals`. Returns `null` on 204 (no active
/// collection) so the rail renders nothing. Auto-refetches every 5 minutes
/// while kept alive.
final flashDealsProvider =
    FutureProvider.autoDispose<FlashDealsCollection?>((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get<Map<String, dynamic>>(
    '/home/flash-deals',
    options: Options(validateStatus: (s) => s != null && s < 500),
  );
  if (resp.statusCode == 204 || resp.data == null) {
    return null;
  }

  // Refetch every 5 minutes (kept alive so the timer survives between frames).
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), ref.invalidateSelf);
  ref.onDispose(() {
    timer.cancel();
    link.close();
  });

  final data = resp.data!;
  final products = (data['products'] as List<dynamic>? ?? [])
      .map((e) => ProductSummary.fromJson(e as Map<String, dynamic>))
      .toList();
  return FlashDealsCollection(
    id: data['id'] as int,
    title: data['title'] as String,
    endsAt: DateTime.parse(data['endsAt'] as String),
    products: products,
  );
});
