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

  // Post-purchase return/refund states (surfaced on the timeline + return detail).
  static const returnRequested = 'return_requested';
  static const returnApproved = 'return_approved';
  static const returnRejected = 'return_rejected';
  static const refundIssued = 'refund_issued';

  static String label(String status) {
    return switch (status) {
      pendingPayment => 'status.pending_payment'.tr(),
      paid => 'status.paid'.tr(),
      shipped => 'status.shipped'.tr(),
      delivered => 'status.delivered'.tr(),
      cancelled => 'status.cancelled'.tr(),
      refunded => 'status.refunded'.tr(),
      partiallyRefunded => 'status.partially_refunded'.tr(),
      returnRequested => 'status.return_requested'.tr(),
      returnApproved => 'status.return_approved'.tr(),
      returnRejected => 'status.return_rejected'.tr(),
      refundIssued => 'status.refund_issued'.tr(),
      _ => status,
    };
  }

  static const postPurchase = {
    returnRequested,
    returnApproved,
    returnRejected,
    refundIssued,
  };

  static bool canCancel(String status) =>
      status == pendingPayment || status == paid;

  static List<String> get timeline => [
        pendingPayment,
        paid,
        shipped,
        delivered,
      ];
}

/// A single order item that may still be returned, with its remaining quantity.
class ReturnableItem {
  const ReturnableItem({required this.itemId, required this.maxQuantity});

  factory ReturnableItem.fromJson(Map<String, dynamic> json) => ReturnableItem(
        itemId: (json['itemId'] as num).toInt(),
        maxQuantity: (json['maxQuantity'] as num).toInt(),
      );

  final int itemId;
  final int maxQuantity;
}

/// Server-computed eligibility block (the client renders CTAs from this — no
/// client-side eligibility math, see SYSTEM_AUDIT §3.1).
class OrderActions {
  const OrderActions({
    this.canCancel = false,
    this.canReturn = false,
    this.returnableUntil,
    this.returnableItems = const [],
  });

  factory OrderActions.fromJson(Map<String, dynamic> json) => OrderActions(
        canCancel: json['canCancel'] as bool? ?? false,
        canReturn: json['canReturn'] as bool? ?? false,
        returnableUntil: json['returnableUntil'] != null
            ? DateTime.tryParse(json['returnableUntil'] as String)
            : null,
        returnableItems: (json['returnableItems'] as List<dynamic>? ?? [])
            .map((e) => ReturnableItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final bool canCancel;
  final bool canReturn;
  final DateTime? returnableUntil;
  final List<ReturnableItem> returnableItems;

  int maxQuantityFor(int itemId) {
    for (final r in returnableItems) {
      if (r.itemId == itemId) return r.maxQuantity;
    }
    return 0;
  }
}

/// Refund status as surfaced on order + return detail.
class RefundStatus {
  static const pending = 'pending';
  static const processing = 'processing';
  static const issued = 'issued';
  static const failed = 'failed';
}

/// Read-only refund visibility block (derived server-side from the payment /
/// return record). Null when no refund is in scope.
class RefundInfo {
  const RefundInfo({
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.status,
    this.issuedAt,
    this.estimatedAt,
  });

  factory RefundInfo.fromJson(Map<String, dynamic> json) => RefundInfo(
        amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
        currency: (json['currency'] as String?) ?? 'TRY',
        method: (json['method'] as String?) ?? 'original_payment',
        status: (json['status'] as String?) ?? RefundStatus.pending,
        issuedAt: json['issuedAt'] != null
            ? DateTime.tryParse(json['issuedAt'] as String)
            : null,
        estimatedAt: json['estimatedAt'] != null
            ? DateTime.tryParse(json['estimatedAt'] as String)
            : null,
      );

  final int amountMinor;
  final String currency;
  final String method; // original_payment | wallet_credit
  final String status; // pending | processing | issued | failed
  final DateTime? issuedAt;
  final DateTime? estimatedAt;

  bool get isWallet => method == 'wallet_credit';
}

/// Immutable ship-to snapshot captured at checkout (OR-02). Null for legacy orders
/// created before address capture — a frozen copy, not a live address reference.
class DeliveryAddressDto {
  const DeliveryAddressDto({
    required this.recipientName,
    required this.fullAddress,
    required this.district,
    required this.city,
    this.label = '',
    this.phone = '',
    this.neighborhood = '',
    this.postalCode = '',
  });

  factory DeliveryAddressDto.fromJson(Map<String, dynamic> json) =>
      DeliveryAddressDto(
        label: (json['label'] as String?) ?? '',
        recipientName: (json['recipient_name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        fullAddress: (json['full_address'] as String?) ?? '',
        neighborhood: (json['neighborhood'] as String?) ?? '',
        district: (json['district'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
        postalCode: (json['postal_code'] as String?) ?? '',
      );

  final String label;
  final String recipientName;
  final String phone;
  final String fullAddress;
  final String neighborhood;
  final String district;
  final String city;
  final String postalCode;

  /// "Mah. ... District/City PostalCode" — the locality line under the street.
  String get localityLine {
    final parts = <String>[
      if (neighborhood.isNotEmpty) neighborhood,
      if (district.isNotEmpty || city.isNotEmpty)
        [district, city].where((s) => s.isNotEmpty).join('/'),
      if (postalCode.isNotEmpty) postalCode,
    ];
    return parts.join(' ');
  }
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
    this.deliveryAddress,
    this.items = const [],
    this.actions,
    this.refund,
  });

  /// Accepts both the flat order object (list items in `data[]`) and the
  /// wrapped detail envelope `{order, items, actions, refund}`.
  factory OrderDto.fromJson(Map<String, dynamic> json) {
    final wrapped = json['order'] is Map<String, dynamic>;
    final o = wrapped ? json['order'] as Map<String, dynamic> : json;
    final itemsJson = (wrapped ? json['items'] : o['items']) as List<dynamic>?;
    return OrderDto(
      id: (o['id'] as num).toInt(),
      userId: (o['user_id'] as num).toInt(),
      sellerId: (o['seller_id'] as num?)?.toInt(),
      status: (o['status'] as String?) ?? OrderStatus.pendingPayment,
      totalMinor: (o['total_minor'] as num).toInt(),
      itemsMinor: (o['items_minor'] as num?)?.toInt(),
      shippingMinor: (o['shipping_minor'] as num?)?.toInt(),
      commissionMinor: (o['commission_minor'] as num?)?.toInt(),
      kdvMinor: (o['kdv_minor'] as num?)?.toInt(),
      currency: (o['currency'] as String?) ?? 'TRY',
      createdAt: DateTime.parse(o['created_at'] as String),
      updatedAt: o['updated_at'] != null
          ? DateTime.tryParse(o['updated_at'] as String)
          : null,
      shippedAt: o['shipped_at'] != null
          ? DateTime.tryParse(o['shipped_at'] as String)
          : null,
      deliveredAt: o['delivered_at'] != null
          ? DateTime.tryParse(o['delivered_at'] as String)
          : null,
      deliveryAddress: o['delivery_address'] is Map<String, dynamic>
          ? DeliveryAddressDto.fromJson(
              o['delivery_address'] as Map<String, dynamic>,
            )
          : null,
      items: (itemsJson ?? [])
          .map((e) => OrderItemDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      actions: json['actions'] is Map<String, dynamic>
          ? OrderActions.fromJson(json['actions'] as Map<String, dynamic>)
          : null,
      refund: json['refund'] is Map<String, dynamic>
          ? RefundInfo.fromJson(json['refund'] as Map<String, dynamic>)
          : null,
    );
  }

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
  final DeliveryAddressDto? deliveryAddress;
  final List<OrderItemDto> items;
  final OrderActions? actions;
  final RefundInfo? refund;

  OrderDto copyWith({
    String? status,
    DateTime? updatedAt,
    OrderActions? actions,
    RefundInfo? refund,
  }) =>
      OrderDto(
        id: id,
        userId: userId,
        sellerId: sellerId,
        status: status ?? this.status,
        totalMinor: totalMinor,
        itemsMinor: itemsMinor,
        shippingMinor: shippingMinor,
        commissionMinor: commissionMinor,
        kdvMinor: kdvMinor,
        currency: currency,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        shippedAt: shippedAt,
        deliveredAt: deliveredAt,
        deliveryAddress: deliveryAddress,
        items: items,
        actions: actions ?? this.actions,
        refund: refund ?? this.refund,
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
        if (deliveredAt != null) 'delivered_at': deliveredAt!.toIso8601String(),
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
