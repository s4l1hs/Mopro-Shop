// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkout_request_payment_method.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckoutRequestPaymentMethod _$CheckoutRequestPaymentMethodFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'CheckoutRequestPaymentMethod',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['type']);
    final val = CheckoutRequestPaymentMethod(
      type: $checkedConvert(
        'type',
        (v) => $enumDecode(_$CheckoutRequestPaymentMethodTypeEnumEnumMap, v),
      ),
      savedCardId: $checkedConvert('saved_card_id', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {'savedCardId': 'saved_card_id'},
);

Map<String, dynamic> _$CheckoutRequestPaymentMethodToJson(
  CheckoutRequestPaymentMethod instance,
) => <String, dynamic>{
  'type': _$CheckoutRequestPaymentMethodTypeEnumEnumMap[instance.type]!,
  if (instance.savedCardId != null) 'saved_card_id': instance.savedCardId,
};

const _$CheckoutRequestPaymentMethodTypeEnumEnumMap = {
  CheckoutRequestPaymentMethodTypeEnum.card: 'card',
  CheckoutRequestPaymentMethodTypeEnum.coinBalance: 'coin_balance',
};
