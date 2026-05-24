// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkout_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckoutResponse _$CheckoutResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CheckoutResponse',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'order_id',
            'status',
            'total_minor',
            'currency',
            'payment',
          ],
        );
        final val = CheckoutResponse(
          orderId: $checkedConvert('order_id', (v) => (v as num).toInt()),
          status: $checkedConvert(
            'status',
            (v) => $enumDecode(_$CheckoutResponseStatusEnumEnumMap, v),
          ),
          totalMinor: $checkedConvert('total_minor', (v) => (v as num).toInt()),
          currency: $checkedConvert('currency', (v) => v as String),
          payment: $checkedConvert(
            'payment',
            (v) => CheckoutResponsePayment.fromJson(v as Map<String, dynamic>),
          ),
        );
        return val;
      },
      fieldKeyMap: const {'orderId': 'order_id', 'totalMinor': 'total_minor'},
    );

Map<String, dynamic> _$CheckoutResponseToJson(CheckoutResponse instance) =>
    <String, dynamic>{
      'order_id': instance.orderId,
      'status': _$CheckoutResponseStatusEnumEnumMap[instance.status]!,
      'total_minor': instance.totalMinor,
      'currency': instance.currency,
      'payment': instance.payment.toJson(),
    };

const _$CheckoutResponseStatusEnumEnumMap = {
  CheckoutResponseStatusEnum.awaitingPayment: 'awaiting_payment',
  CheckoutResponseStatusEnum.confirmed: 'confirmed',
};
