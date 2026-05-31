import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';

abstract class NotificationRepository {
  Future<NotificationListResult> list({
    bool unreadOnly = false,
    int page = 1,
    int pageSize = 20,
  });
  Future<int> unreadCount();
  Future<void> markRead(int id);
  Future<int> markAllRead();
  Future<List<PreferenceDto>> getPreferences();
  Future<void> putPreferences(List<PreferenceDto> prefs);
  Future<void> registerPushToken({required String token, required String platform});
  Future<void> deletePushToken(String token);
}

class NotificationRepositoryImpl implements NotificationRepository {
  const NotificationRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<NotificationListResult> list({
    bool unreadOnly = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: {
        'filter': unreadOnly ? 'unread' : 'all',
        'page': page,
        'pageSize': pageSize,
      },
    );
    return NotificationListResult.fromJson(resp.data!);
  }

  @override
  Future<int> unreadCount() async {
    final resp = await _dio.get<Map<String, dynamic>>('/notifications/unread-count');
    return (resp.data!['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> markRead(int id) async {
    await _dio.post<void>('/notifications/$id/read');
  }

  @override
  Future<int> markAllRead() async {
    final resp = await _dio.post<Map<String, dynamic>>('/notifications/read-all');
    return (resp.data?['marked'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<PreferenceDto>> getPreferences() async {
    final resp = await _dio.get<Map<String, dynamic>>('/notifications/preferences');
    return (resp.data!['preferences'] as List<dynamic>)
        .map((e) => PreferenceDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> putPreferences(List<PreferenceDto> prefs) async {
    await _dio.put<void>(
      '/notifications/preferences',
      data: {'preferences': prefs.map((p) => p.toJson()).toList()},
    );
  }

  @override
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    await _dio.post<void>('/push-tokens', data: {'token': token, 'platform': platform});
  }

  @override
  Future<void> deletePushToken(String token) async {
    await _dio.delete<void>('/push-tokens', data: {'token': token});
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepositoryImpl(ref.watch(dioProvider));
});
