import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro_api/mopro_api.dart';

/// View-model for the authed user's identity, exposed for menu headers,
/// profile chrome, and anywhere else the display name / email is shown.
///
/// Source: `MeApi.getMe()` (i.e. `GET /me`). Cached per session and
/// invalidated when [authNotifierProvider] transitions out of
/// `AuthAuthenticated` (e.g. logout). Guest sessions return `null` without
/// touching the network.
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.sellerBinding,
  });

  final int id;

  /// The user's seller-account binding from `/me`, or null when not a seller.
  /// Drives `userIsSellerProvider` + the seller dashboard. (Tranche 5 seller UI.)
  final SellerBinding? sellerBinding;

  /// Computed: `name_first + ' ' + name_last` when both present, else
  /// `name_first`, else local-part of the email, else null.
  final String displayName;
  final String? email;

  /// Server-provided avatar URL. The DTO doesn't carry one yet, so this is
  /// always null for now — kept on the model so consumers don't need to
  /// reshape when the backend lands the field.
  final String? avatarUrl;

  /// 1-2 character initials derived from [displayName]. Falls back to "M" on
  /// empty input.
  String get initials {
    final source = displayName.trim();
    if (source.isEmpty) return 'M';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts.first[0] + parts[1][0]).toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }
}

/// Async view of the current authed user. Returns `AsyncData(null)` for
/// guests so consumers can render placeholder UI without an error branch.
final currentUserProvider = FutureProvider<CurrentUser?>((ref) async {
  final auth = ref.watch(authNotifierProvider).valueOrNull;
  if (auth is! AuthAuthenticated) return null;

  final api = ref.read(meApiProvider);
  try {
    final resp = await api.getMe();
    final user = resp.data;
    if (user == null) return null;

    final first = user.nameFirst?.trim() ?? '';
    final last = user.nameLast?.trim() ?? '';
    String name;
    if (first.isNotEmpty && last.isNotEmpty) {
      name = '$first $last';
    } else if (first.isNotEmpty) {
      name = first;
    } else if ((user.email ?? '').contains('@')) {
      name = user.email!.split('@').first;
    } else {
      name = '';
    }

    return CurrentUser(
      id: user.id,
      displayName: name,
      email: user.email,
      sellerBinding: user.sellerBinding,
    );
  } on DioException {
    // Network errors surface as AsyncError; UI shows fallback header.
    rethrow;
  }
});
