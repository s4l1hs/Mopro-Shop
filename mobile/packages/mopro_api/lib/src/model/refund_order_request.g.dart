// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'refund_order_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RefundOrderRequest _$RefundOrderRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RefundOrderRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['reason']);
      final val = RefundOrderRequest(
        reason: $checkedConvert('reason', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$RefundOrderRequestToJson(RefundOrderRequest instance) =>
    <String, dynamic>{'reason': instance.reason};
