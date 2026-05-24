// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkout_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CheckoutRequest _$CheckoutRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CheckoutRequest',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const ['address_id', 'cargo_option', 'payment_method'],
        );
        final val = CheckoutRequest(
          addressId: $checkedConvert('address_id', (v) => (v as num).toInt()),
          cargoOption: $checkedConvert(
            'cargo_option',
            (v) => $enumDecode(_$CheckoutRequestCargoOptionEnumEnumMap, v),
          ),
          paymentMethod: $checkedConvert(
            'payment_method',
            (v) => CheckoutRequestPaymentMethod.fromJson(
              v as Map<String, dynamic>,
            ),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'addressId': 'address_id',
        'cargoOption': 'cargo_option',
        'paymentMethod': 'payment_method',
      },
    );

Map<String, dynamic> _$CheckoutRequestToJson(CheckoutRequest instance) =>
    <String, dynamic>{
      'address_id': instance.addressId,
      'cargo_option':
          _$CheckoutRequestCargoOptionEnumEnumMap[instance.cargoOption]!,
      'payment_method': instance.paymentMethod.toJson(),
    };

const _$CheckoutRequestCargoOptionEnumEnumMap = {
  CheckoutRequestCargoOptionEnum.aras: 'aras',
  CheckoutRequestCargoOptionEnum.yurtici: 'yurtici',
  CheckoutRequestCargoOptionEnum.surat: 'surat',
  CheckoutRequestCargoOptionEnum.mng: 'mng',
  CheckoutRequestCargoOptionEnum.hepsijet: 'hepsijet',
  CheckoutRequestCargoOptionEnum.ptt: 'ptt',
};
