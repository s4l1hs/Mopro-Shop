import 'package:dio/dio.dart';
import 'package:mopro/features/checkout/data/checkout_repository.dart';
import 'package:mopro/features/checkout/data/checkout_response_dto.dart';

class CheckoutRepositoryImpl implements CheckoutRepository {
  const CheckoutRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<CheckoutResponseDto> initiate({
    required String buyerName,
    required String buyerSurname,
    required String idempotencyKey,
    String returnUrl = 'mopro://checkout/result',
    String couponCode = '',
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/checkout/initiate',
      data: {
        'buyer_name': buyerName,
        'buyer_surname': buyerSurname,
        'buyer_email': '',
        'return_url': returnUrl,
        if (couponCode.isNotEmpty) 'coupon_code': couponCode,
      },
      options: Options(
        headers: {'Idempotency-Key': idempotencyKey},
      ),
    );
    return CheckoutResponseDto.fromJson(resp.data!);
  }
}
