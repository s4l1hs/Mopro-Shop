// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_cart_item_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AddCartItemRequest _$AddCartItemRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AddCartItemRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['variant_id', 'quantity']);
      final val = AddCartItemRequest(
        variantId: $checkedConvert('variant_id', (v) => (v as num).toInt()),
        quantity: $checkedConvert('quantity', (v) => (v as num).toInt()),
      );
      return val;
    }, fieldKeyMap: const {'variantId': 'variant_id'});

Map<String, dynamic> _$AddCartItemRequestToJson(AddCartItemRequest instance) =>
    <String, dynamic>{
      'variant_id': instance.variantId,
      'quantity': instance.quantity,
    };
