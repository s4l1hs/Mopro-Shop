import 'package:easy_localization/easy_localization.dart';
import 'package:mopro/features/order/data/order_item_dto.dart';

/// Order status strings as returned by Phase 4.5a backend.
class OrderStatus {
  static const pendingPayment = 'pending_payment';
  static const paid = 'paid';
  static const shipped = 'shipped';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';
  static const refunded = 'refunded';
  static const partiallyRefunded = 'partially_refunded';

  static String label(String status) {
    return switch (status) {
      pendingPayment => 'status.pending_payment'.tr(),
      paid => 'status.paid'.tr(),
      shipped => 'status.shipped'.tr(),
      delivered => 'status.delivered'.tr(),
      cancelled => 'status.cancelled'.tr(),
      refunded => 'status.refunded'.tr(),
      partiallyRefunded => 'status.partially_refunded'.tr(),
      _ => status,
    };
  }

  static bool canCancel(String status) =>
      status == pendingPayment || status == paid;

  static List<String> get timeline => [
        pendingPayment,
        paid,
        shipped,
        delivered,
      ];
}

class OrderDto {
  const OrderDto({
    required this.id,
    required this.userId,
    required this.status,
    required this.totalMinor,
    required this.currency,
    required this.createdAt,
    this.sellerId,
    this.itemsMinor,
    this.shippingMinor,
    this.commissionMinor,
    this.kdvMinor,
    this.updatedAt,
    this.shippedAt,
    this.deliveredAt,
    this.items = const [],
  });

  final int id;
  final int userId;
  final int? sellerId;
  final String status;
  final int totalMinor;
  final int? itemsMinor;
  final int? shippingMinor;
  final int? commissionMinor;
  final int? kdvMinor;
  final String currency;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  final List<OrderItemDto> items;

  factory OrderDto.fromJson(Map<String, dynamic> json) => OrderDto(
        id: (json['id'] as num).toInt(),
        userId: (json['user_id'] as num).toInt(),
        sellerId: (json['seller_id'] as num?)?.toInt(),
        status: (json['status'] as String?) ?? OrderStatus.pendingPayment,
        totalMinor: (json['total_minor'] as num).toInt(),
        itemsMinor: (json['items_minor'] as num?)?.toInt(),
        shippingMinor: (json['shipping_minor'] as num?)?.toInt(),
        commissionMinor: (json['commission_minor'] as num?)?.toInt(),
        kdvMinor: (json['kdv_minor'] as num?)?.toInt(),
        currency: (json['currency'] as String?) ?? 'TRY',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
        shippedAt: json['shipped_at'] != null
            ? DateTime.tryParse(json['shipped_at'] as String)
            : null,
        deliveredAt: json['delivered_at'] != null
            ? DateTime.tryParse(json['delivered_at'] as String)
            : null,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => OrderItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        if (sellerId != null) 'seller_id': sellerId,
        'status': status,
        'total_minor': totalMinor,
        if (itemsMinor != null) 'items_minor': itemsMinor,
        if (shippingMinor != null) 'shipping_minor': shippingMinor,
        if (commissionMinor != null) 'commission_minor': commissionMinor,
        if (kdvMinor != null) 'kdv_minor': kdvMinor,
        'currency': currency,
        'created_at': createdAt.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        if (shippedAt != null) 'shipped_at': shippedAt!.toIso8601String(),
        if (deliveredAt != null)
          'delivered_at': deliveredAt!.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };
}

class OrderListResult {
  const OrderListResult({
    required this.data,
    required this.hasMore,
    required this.totalPages,
    required this.currentPage,
  });

  final List<OrderDto> data;
  final bool hasMore;
  final int totalPages;
  final int currentPage;
}
