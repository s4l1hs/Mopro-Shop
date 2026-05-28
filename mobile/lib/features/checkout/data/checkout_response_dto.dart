import 'package:mopro/features/order/data/order_dto.dart';

/// Response from POST /checkout/initiate.
///
/// Backend returns:
///   session_id      — checkout session identifier (also used as invoice_id for polling)
///   sipay_3ds_url   — Sipay 3DS redirect URL; web clients use window.location.assign
///   orders          — created order summaries
class CheckoutResponseDto {
  const CheckoutResponseDto({
    required this.sessionId,
    required this.sipayThreeDsUrl,
    required this.orders,
  });

  factory CheckoutResponseDto.fromJson(Map<String, dynamic> json) =>
      CheckoutResponseDto(
        sessionId: (json['session_id'] ?? '') as String,
        sipayThreeDsUrl: (json['sipay_3ds_url'] ?? '') as String,
        orders: (json['orders'] as List<dynamic>? ?? [])
            .map((e) => OrderDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String sessionId;
  final String sipayThreeDsUrl;
  final List<OrderDto> orders;

  bool get requires3ds => sipayThreeDsUrl.isNotEmpty;
}
