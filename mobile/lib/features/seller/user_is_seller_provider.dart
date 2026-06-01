import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Whether the current user is bound to a seller account. Derived from
/// [currentUserProvider] (the `/me` `seller_binding`) — auth state is the source
/// of truth; this is a fact about it, never its own network call. Rebuilds when
/// auth/user state changes. False for guests + non-sellers.
final userIsSellerProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.sellerBinding != null;
});

/// The current user's seller binding (id/slug/name/role), or null when not a
/// seller. For screens needing the seller's identity (dashboard header, storefront
/// link). Same derivation as [userIsSellerProvider].
final currentSellerBindingProvider = Provider<SellerBinding?>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.sellerBinding;
});
