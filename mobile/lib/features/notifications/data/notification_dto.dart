/// Notification type constants (mirror inbox_schema.notifications.type).
class NotificationType {
  static const orderStatus = 'order_status';
  static const returnUpdate = 'return_update';
  static const security = 'security';
  static const marketing = 'marketing';
  static const system = 'system';
}

class NotificationDto {
  const NotificationDto({
    required this.id,
    required this.type,
    required this.titleKey,
    required this.bodyKey,
    required this.createdAt,
    this.bodyParams = const {},
    this.deepLink,
    this.isRead = false,
    this.readAt,
  });

  factory NotificationDto.fromJson(Map<String, dynamic> json) => NotificationDto(
        id: (json['id'] as num).toInt(),
        type: (json['type'] as String?) ?? NotificationType.system,
        titleKey: (json['title_key'] as String?) ?? '',
        bodyKey: (json['body_key'] as String?) ?? '',
        bodyParams: (json['body_params'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, '$v')),
        deepLink: json['deep_link'] as String?,
        isRead: json['is_read'] as bool? ?? false,
        readAt: json['read_at'] != null
            ? DateTime.tryParse(json['read_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final String type;
  final String titleKey;
  final String bodyKey;
  final Map<String, String> bodyParams;
  final String? deepLink;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  NotificationDto copyWith({bool? isRead, DateTime? readAt}) => NotificationDto(
        id: id,
        type: type,
        titleKey: titleKey,
        bodyKey: bodyKey,
        bodyParams: bodyParams,
        deepLink: deepLink,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        createdAt: createdAt,
      );
}

class NotificationListResult {
  const NotificationListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  factory NotificationListResult.fromJson(Map<String, dynamic> json) =>
      NotificationListResult(
        items: (json['data'] as List<dynamic>? ?? [])
            .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 1,
        pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
        hasMore: json['hasMore'] as bool? ?? false,
      );

  final List<NotificationDto> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;
}

/// Preference channel constants.
class NotificationChannel {
  static const inApp = 'in_app';
  static const email = 'email';
  static const push = 'push';
}

class PreferenceDto {
  const PreferenceDto({
    required this.category,
    required this.channel,
    required this.enabled,
  });

  factory PreferenceDto.fromJson(Map<String, dynamic> json) => PreferenceDto(
        category: json['category'] as String,
        channel: json['channel'] as String,
        enabled: json['enabled'] as bool? ?? false,
      );

  final String category;
  final String channel;
  final bool enabled;

  Map<String, dynamic> toJson() =>
      {'category': category, 'channel': channel, 'enabled': enabled};

  PreferenceDto copyWith({bool? enabled}) => PreferenceDto(
        category: category,
        channel: channel,
        enabled: enabled ?? this.enabled,
      );
}
