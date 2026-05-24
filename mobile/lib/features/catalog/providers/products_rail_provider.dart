import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro_api/mopro_api.dart';

final productsRailProvider = FutureProvider.autoDispose
    .family<List<ProductSummary>, String>((ref, sort) async {
  final api = ref.read(catalogApiProvider);
  final resp = await api.listProducts(sort: sort, perPage: 6);
  return resp.data?.data ?? [];
});
