import 'package:mopro/features/checkout/data/checkout_response_dto.dart';

abstract class CheckoutRepository {
  Future<CheckoutResponseDto> initiate({
    required String buyerName,
    required String buyerSurname,
    required String idempotencyKey,
    int? addressId, // OR-02: selected delivery address, snapshotted on the order
    String returnUrl = 'mopro://checkout/result',
    String couponCode = '', // CT-03/CHK-04: charges the cart's coupon-discounted total
  });
}
