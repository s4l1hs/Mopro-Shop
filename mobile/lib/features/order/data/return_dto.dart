import 'package:easy_localization/easy_localization.dart';
import 'package:mopro/features/order/data/order_dto.dart';

/// Return reason codes (the single-per-return OpenAPI enum).
class ReturnReason {
  static const wrongProduct = 'wrong_product';
  static const notAsDescribed = 'not_as_described';
  static const damaged = 'damaged';
  static const sizeIssue = 'size_issue';
  static const changedMind = 'changed_mind';
  static const other = 'other';

  static const all = [
    wrongProduct,
    notAsDescribed,
    damaged,
    sizeIssue,
    changedMind,
    other,
  ];

  static String label(String code) => 'returns.reason_$code'.tr();
}

/// Per-return lifecycle status.
class ReturnLifecycle {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const refunded = 'refunded';

  static String label(String s) => 'returns.status_$s'.tr();
}

/// One status-history event (RT-04): the append-only return audit trail.
class ReturnStatusEventDto {
  const ReturnStatusEventDto({
    required this.status,
    required this.createdAt,
    this.note = '',
  });

  factory ReturnStatusEventDto.fromJson(Map<String, dynamic> json) =>
      ReturnStatusEventDto(
        status: (json['status'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String status;
  final String note;
  final DateTime createdAt;
}

/// One item line within a return. RT-05: carries an optional per-line reason +
/// note (null/empty reason → the header reason applies).
class ReturnItemDto {
  const ReturnItemDto({
    required this.orderItemId,
    required this.quantity,
    this.reason,
    this.note = '',
  });

  factory ReturnItemDto.fromJson(Map<String, dynamic> json) => ReturnItemDto(
        orderItemId: (json['order_item_id'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        reason: json['reason'] as String?,
        note: (json['note'] as String?) ?? '',
      );

  final int orderItemId;
  final int quantity;
  final String? reason;
  final String note;
}

/// Compact return for the "İadelerim" list (matches GET /returns data[]).
class ReturnListItemDto {
  const ReturnListItemDto({
    required this.id,
    required this.orderId,
    required this.status,
    required this.reason,
    required this.refundAmountMinor,
    required this.refundCurrency,
    required this.createdAt,
  });

  factory ReturnListItemDto.fromJson(Map<String, dynamic> json) =>
      ReturnListItemDto(
        id: (json['id'] as num).toInt(),
        orderId: (json['order_id'] as num).toInt(),
        status: (json['status'] as String?) ?? ReturnLifecycle.pending,
        reason: (json['reason'] as String?) ?? ReturnReason.other,
        refundAmountMinor: (json['refund_amount_minor'] as num?)?.toInt() ?? 0,
        refundCurrency: (json['refund_currency'] as String?) ?? 'TRY',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final int orderId;
  final String status;
  final String reason;
  final int refundAmountMinor;
  final String refundCurrency;
  final DateTime createdAt;
}

/// RT-02: the return cargo block — a stable return cargo code (İade Kargo Kodu,
/// our own id-derived code, not a live carrier tracking number) + the carrier.
class ReturnShippingDto {
  const ReturnShippingDto({required this.code, required this.carrier});

  factory ReturnShippingDto.fromJson(Map<String, dynamic> json) =>
      ReturnShippingDto(
        code: (json['code'] as String?) ?? '',
        carrier: (json['carrier'] as String?) ?? '',
      );

  final String code;
  final String carrier;
}

/// Full return detail (matches GET /returns/{id} and the POST /returns response).
class ReturnDetailDto {
  const ReturnDetailDto({
    required this.id,
    required this.orderId,
    required this.status,
    required this.reason,
    required this.createdAt,
    this.description = '',
    this.items = const [],
    this.history = const [],
    this.photoUrls = const [],
    this.shipping,
    this.refund,
  });

  factory ReturnDetailDto.fromJson(Map<String, dynamic> json) =>
      ReturnDetailDto(
        id: (json['id'] as num).toInt(),
        orderId: (json['order_id'] as num).toInt(),
        status: (json['status'] as String?) ?? ReturnLifecycle.pending,
        reason: (json['reason'] as String?) ?? ReturnReason.other,
        description: (json['description'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => ReturnItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: (json['history'] as List<dynamic>? ?? [])
            .map((e) => ReturnStatusEventDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        photoUrls: (json['photo_urls'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        shipping: json['shipping'] is Map<String, dynamic>
            ? ReturnShippingDto.fromJson(json['shipping'] as Map<String, dynamic>)
            : null,
        refund: json['refund'] is Map<String, dynamic>
            ? RefundInfo.fromJson(json['refund'] as Map<String, dynamic>)
            : null,
      );

  final int id;
  final int orderId;
  final String status;
  final String reason;
  final String description;
  final DateTime createdAt;
  final List<ReturnItemDto> items;

  /// RT-04: the append-only status timeline; empty for pre-history returns →
  /// the detail falls back to the status-derived timeline.
  final List<ReturnStatusEventDto> history;

  /// RT-03: evidence photo CDN urls (empty when none / capture not yet wired).
  final List<String> photoUrls;

  /// RT-02: the return cargo code + carrier (null on pre-RT-02 responses).
  final ReturnShippingDto? shipping;
  final RefundInfo? refund;
}

/// Request body for POST /orders/{id}/returns.
class CreateReturnRequest {
  const CreateReturnRequest({
    required this.orderId,
    required this.reason,
    this.description = '',
    this.items = const [],
    this.photoKeys = const [],
  });

  final int orderId;
  final String reason;
  final String description;
  final List<ReturnItemDto> items;

  /// RT-03: evidence photo storage keys. Populated once the capture step (mobile
  /// picker + upload) lands — gated on storage provisioning.
  final List<String> photoKeys;

  Map<String, dynamic> toJson() => {
        'reason': reason,
        if (description.isNotEmpty) 'description': description,
        if (photoKeys.isNotEmpty) 'photo_keys': photoKeys,
        if (items.isNotEmpty)
          'items': [
            for (final i in items)
              {
                'order_item_id': i.orderItemId,
                'quantity': i.quantity,
                // RT-05: per-line reason + note (omitted when empty → header applies).
                if (i.reason != null && i.reason!.isNotEmpty) 'reason': i.reason,
                if (i.note.isNotEmpty) 'note': i.note,
              },
          ],
      };
}
