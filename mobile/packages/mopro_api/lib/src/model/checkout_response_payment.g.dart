// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkout_response_payment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckoutResponsePayment _$CheckoutResponsePaymentFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'CheckoutResponsePayment',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['requires_3ds']);
    final val = CheckoutResponsePayment(
      requires3ds: $checkedConvert('requires_3ds', (v) => v as bool),
      redirectUrl: $checkedConvert('redirect_url', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'requires3ds': 'requires_3ds',
    'redirectUrl': 'redirect_url',
  },
);

Map<String, dynamic> _$CheckoutResponsePaymentToJson(
  CheckoutResponsePayment instance,
) => <String, dynamic>{
  'requires_3ds': instance.requires3ds,
  if (instance.redirectUrl != null) 'redirect_url': instance.redirectUrl,
};
