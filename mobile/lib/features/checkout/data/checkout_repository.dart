import 'package:mopro/features/checkout/data/checkout_response_dto.dart';

abstract class CheckoutRepository {
  Future<CheckoutResponseDto> initiate({
    required int addressId,
    required String paymentMethod,
    required String idempotencyKey,
  });
}
