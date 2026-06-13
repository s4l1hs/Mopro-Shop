import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro_api/mopro_api.dart';

/// Size-fit phase 1 (docs/internal/size-fit.md).
/// The user's fit profile (measurements arrive in mm; stored encrypted
/// server-side). autoDispose → refetches on next visit.
final AutoDisposeFutureProvider<FitProfileEnvelope?> fitProfileProvider =
    FutureProvider.autoDispose<FitProfileEnvelope?>((ref) async {
  final resp = await ref.watch(meApiProvider).getMyFitProfile();
  return resp.data;
});

/// Per-product size recommendation. Null on any failure — the PDP card is
/// enrichment, never a blocker (mirrors the membership-card pattern).
final AutoDisposeFutureProviderFamily<SizeRecommendation?, int>
    sizeRecommendationProvider =
    FutureProvider.autoDispose.family<SizeRecommendation?, int>(
        (ref, productId) async {
  try {
    final resp =
        await ref.watch(catalogApiProvider).getSizeRecommendation(id: productId);
    return resp.data;
  } on Object {
    return null;
  }
});
