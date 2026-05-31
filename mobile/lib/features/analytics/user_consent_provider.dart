import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';

/// Immutable analytics-consent state (binary opt-in, Decision 3). Backed by
/// `GET/PUT /me/consent`. Follows Notifier shape #1.
class UserConsent {
  const UserConsent({
    this.analyticsEnabled = false,
    this.consentedAt,
    this.revokedAt,
    this.loading = false,
    this.authed = false,
  });

  factory UserConsent.fromJson(Map<String, dynamic> j) => UserConsent(
        analyticsEnabled: (j['analyticsEnabled'] as bool?) ?? false,
        consentedAt: DateTime.tryParse((j['consentedAt'] as String?) ?? ''),
        revokedAt: DateTime.tryParse((j['revokedAt'] as String?) ?? ''),
        authed: true,
      );

  final bool analyticsEnabled;
  final DateTime? consentedAt;
  final DateTime? revokedAt;
  final bool loading;
  final bool authed;

  /// True once the user has made a choice (accepted or declined). Drives whether
  /// the first-visit banner still needs to show.
  bool get decided => consentedAt != null || revokedAt != null;

  UserConsent copyWith({
    bool? analyticsEnabled,
    DateTime? consentedAt,
    DateTime? revokedAt,
    bool? loading,
    bool? authed,
  }) =>
      UserConsent(
        analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
        consentedAt: consentedAt ?? this.consentedAt,
        revokedAt: revokedAt ?? this.revokedAt,
        loading: loading ?? this.loading,
        authed: authed ?? this.authed,
      );
}

class UserConsentNotifier extends Notifier<UserConsent> {
  @override
  UserConsent build() {
    final authed =
        ref.watch(authNotifierProvider).valueOrNull is AuthAuthenticated;
    if (!authed) {
      // Guests have no consent row; banner/settings are authed-only.
      return const UserConsent();
    }
    Future<void>.microtask(_loadInitial);
    return const UserConsent(loading: true, authed: true);
  }

  Dio get _dio => ref.read(dioProvider);

  Future<void> _loadInitial() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/me/consent');
      state = UserConsent.fromJson(resp.data ?? const {});
    } catch (_) {
      // On error treat as undecided-but-loaded; banner stays hidden to avoid a
      // flash on a transient failure (recently-viewed-style silent degrade).
      state = const UserConsent(authed: true);
    }
  }

  /// Optimistically sets consent then persists; rolls back on failure.
  /// Returns true on success. (Positional bool: setConsent(true/false) reads
  /// naturally and mirrors the notification toggle API shape.)
  // ignore: avoid_positional_boolean_parameters
  Future<bool> setConsent(bool enabled) async {
    final prev = state;
    final now = DateTime.now();
    state = state.copyWith(
      analyticsEnabled: enabled,
      consentedAt: enabled ? now : null,
      revokedAt: enabled ? null : now,
      loading: false,
    );
    try {
      final resp = await _dio.put<Map<String, dynamic>>(
        '/me/consent',
        data: <String, dynamic>{'analyticsEnabled': enabled},
      );
      state = UserConsent.fromJson(resp.data ?? const {});
      return true;
    } catch (_) {
      state = prev;
      return false;
    }
  }

  /// RTBF erase (Decision 5). Returns true on success. Consent state is
  /// unchanged (the user may keep tracking on or off independently).
  Future<bool> deleteAllData() async {
    try {
      await _dio.delete<void>('/me/analytics-data');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final userConsentProvider =
    NotifierProvider<UserConsentNotifier, UserConsent>(UserConsentNotifier.new);
