import 'package:mopro/features/order/data/order_dto.dart';

/// Response from POST /v1/checkout/initiate.
///
/// The backend Phase 4.5a returns:
///   session_id     — checkout session identifier
///   three_ds_html  — Sipay 3DS form HTML to render in WebView
///   orders         — created order summaries
class CheckoutResponseDto {
  const CheckoutResponseDto({
    required this.sessionId,
    required this.threeDsHtml,
    required this.orders,
  });

  final String sessionId;
  final String threeDsHtml;
  final List<OrderDto> orders;

  bool get requires3ds => threeDsHtml.isNotEmpty;

  factory CheckoutResponseDto.fromJson(Map<String, dynamic> json) =>
      CheckoutResponseDto(
        sessionId: (json['session_id'] ?? '') as String,
        threeDsHtml: (json['three_ds_html'] ?? '') as String,
        orders: (json['orders'] as List<dynamic>? ?? [])
            .map((e) => OrderDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
