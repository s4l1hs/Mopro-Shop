import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';
import 'package:mopro/features/notifications/data/notification_repository.dart';

enum NotificationFilter { all, unread }

/// Unread-count badge source: polls every 60s while an authenticated user is
/// present, and exposes a refresh for after-action refetch. 0 for guests.
final unreadNotificationCountProvider =
    NotifierProvider<UnreadCountNotifier, int>(UnreadCountNotifier.new);

class UnreadCountNotifier extends Notifier<int> {
  Timer? _timer;
  bool _disposed = false;

  @override
  int build() {
    final authed = ref.watch(authNotifierProvider).valueOrNull is AuthAuthenticated;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    _timer?.cancel();
    if (!authed) return 0;
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    try {
      final n = await ref.read(notificationRepositoryProvider).unreadCount();
      if (!_disposed) state = n;
    } catch (_) {
      // Soft-fail: keep the last known count on transient errors.
    }
  }

  void decrement([int by = 1]) {
    state = (state - by).clamp(0, 1 << 30);
  }

  void clear() => state = 0;
}

class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  final List<NotificationDto> items;
  final int total;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final AppError? error;

  NotificationsState copyWith({
    List<NotificationDto>? items,
    int? total,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    AppError? error,
    bool clearError = false,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

final notificationsProvider = NotifierProviderFamily<NotificationsNotifier,
    NotificationsState, NotificationFilter>(NotificationsNotifier.new);

/// Shape #1: build() returns a default state and defers the first fetch.
class NotificationsNotifier
    extends FamilyNotifier<NotificationsState, NotificationFilter> {
  @override
  NotificationsState build(NotificationFilter arg) {
    Future.microtask(_loadFirst);
    return const NotificationsState();
  }

  NotificationRepository get _repo => ref.read(notificationRepositoryProvider);

  Future<void> _loadFirst() async {
    try {
      final res = await _repo.list(unreadOnly: arg == NotificationFilter.unread);
      state = state.copyWith(
        items: res.items,
        total: res.total,
        page: res.page,
        hasMore: res.hasMore,
        loading: false,
        clearError: true,
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _err(e));
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: UnknownError(statusCode: 0, message: e.toString()),
      );
    }
  }

  Future<void> refresh() {
    state = state.copyWith(loading: true, page: 1, clearError: true);
    return _loadFirst();
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final res = await _repo.list(
        unreadOnly: arg == NotificationFilter.unread,
        page: state.page + 1,
      );
      state = state.copyWith(
        items: [...state.items, ...res.items],
        page: res.page,
        hasMore: res.hasMore,
        loadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(loadingMore: false);
    }
  }

  /// Optimistic mark-read with rollback on failure. Also nudges the badge.
  Future<void> markRead(int id) async {
    final prev = state.items;
    state = state.copyWith(
      items: [
        for (final n in prev) n.id == id ? n.copyWith(isRead: true, readAt: DateTime.now()) : n,
      ],
    );
    ref.read(unreadNotificationCountProvider.notifier).decrement();
    try {
      await _repo.markRead(id);
    } catch (_) {
      state = state.copyWith(items: prev); // rollback
      unawaited(ref.read(unreadNotificationCountProvider.notifier).refresh());
    }
  }

  Future<void> markAllRead() async {
    final prev = state.items;
    state = state.copyWith(
      items: [for (final n in prev) n.copyWith(isRead: true, readAt: DateTime.now())],
    );
    ref.read(unreadNotificationCountProvider.notifier).clear();
    try {
      await _repo.markAllRead();
    } catch (_) {
      state = state.copyWith(items: prev);
      unawaited(ref.read(unreadNotificationCountProvider.notifier).refresh());
    }
  }

  AppError _err(DioException e) {
    final err = e.error;
    return err is AppError ? err : NetworkError(message: e.message ?? '');
  }
}
