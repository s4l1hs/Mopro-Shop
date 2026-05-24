// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_return.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModelReturn _$ModelReturnFromJson(Map<String, dynamic> json) => $checkedCreate(
  'ModelReturn',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const ['id', 'order_id', 'status', 'reason', 'created_at'],
    );
    final val = ModelReturn(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      orderId: $checkedConvert('order_id', (v) => (v as num).toInt()),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$ModelReturnStatusEnumEnumMap, v),
      ),
      reason: $checkedConvert('reason', (v) => v as String),
      description: $checkedConvert('description', (v) => v as String?),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {'orderId': 'order_id', 'createdAt': 'created_at'},
);

Map<String, dynamic> _$ModelReturnToJson(ModelReturn instance) =>
    <String, dynamic>{
      'id': instance.id,
      'order_id': instance.orderId,
      'status': _$ModelReturnStatusEnumEnumMap[instance.status]!,
      'reason': instance.reason,
      if (instance.description != null) 'description': instance.description,
      'created_at': instance.createdAt.toIso8601String(),
    };

const _$ModelReturnStatusEnumEnumMap = {
  ModelReturnStatusEnum.pending: 'pending',
  ModelReturnStatusEnum.approved: 'approved',
  ModelReturnStatusEnum.rejected: 'rejected',
  ModelReturnStatusEnum.refunded: 'refunded',
};
