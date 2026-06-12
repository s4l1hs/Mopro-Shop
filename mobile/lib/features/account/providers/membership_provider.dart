import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro_api/mopro_api.dart';

/// AC-05: the authenticated user's derived membership tier
/// (GET /me/membership). autoDispose: refetches on next visit, so the badge
/// tracks order activity without manual invalidation.
final AutoDisposeFutureProvider<Membership?> membershipProvider =
    FutureProvider.autoDispose<Membership?>((ref) async {
  final resp = await ref.watch(meApiProvider).getMyMembership();
  return resp.data;
});
