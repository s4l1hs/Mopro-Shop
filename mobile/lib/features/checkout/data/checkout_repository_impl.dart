import 'package:dio/dio.dart';
import 'package:mopro/features/checkout/data/checkout_repository.dart';
import 'package:mopro/features/checkout/data/checkout_response_dto.dart';

class CheckoutRepositoryImpl implements CheckoutRepository {
  const CheckoutRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<CheckoutResponseDto> initiate({
    required int addressId,
    required String paymentMethod,
    required String idempotencyKey,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/checkout/initiate',
      data: {
        'address_id': addressId,
        'payment_method': paymentMethod,
      },
      options: Options(
        headers: {'Idempotency-Key': idempotencyKey},
      ),
    );
    return CheckoutResponseDto.fromJson(resp.data!);
  }
}
