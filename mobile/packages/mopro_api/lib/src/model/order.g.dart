// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Order _$OrderFromJson(Map<String, dynamic> json) => $checkedCreate(
  'Order',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'user_id',
        'status',
        'items',
        'total_minor',
        'currency',
        'created_at',
      ],
    );
    final val = Order(
      id: $checkedConvert('id', (v) => (v as num).toInt()),
      userId: $checkedConvert('user_id', (v) => (v as num).toInt()),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$OrderStatusEnumEnumMap, v),
      ),
      items: $checkedConvert(
        'items',
        (v) => (v as List<dynamic>)
            .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      totalMinor: $checkedConvert('total_minor', (v) => (v as num).toInt()),
      currency: $checkedConvert('currency', (v) => v as String),
      cargoOption: $checkedConvert(
        'cargo_option',
        (v) => $enumDecodeNullable(_$OrderCargoOptionEnumEnumMap, v),
      ),
      cashbackUnlockAt: $checkedConvert(
        'cashback_unlock_at',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      deliveredAt: $checkedConvert(
        'delivered_at',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      deliveryAddress: $checkedConvert(
        'delivery_address',
        (v) => v == null
            ? null
            : DeliveryAddress.fromJson(v as Map<String, dynamic>),
      ),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'totalMinor': 'total_minor',
    'cargoOption': 'cargo_option',
    'cashbackUnlockAt': 'cashback_unlock_at',
    'deliveredAt': 'delivered_at',
    'deliveryAddress': 'delivery_address',
    'createdAt': 'created_at',
  },
);

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'status': _$OrderStatusEnumEnumMap[instance.status]!,
  'items': instance.items.map((e) => e.toJson()).toList(),
  'total_minor': instance.totalMinor,
  'currency': instance.currency,
  'cargo_option': ?_$OrderCargoOptionEnumEnumMap[instance.cargoOption],
  'cashback_unlock_at': ?instance.cashbackUnlockAt?.toIso8601String(),
  'delivered_at': ?instance.deliveredAt?.toIso8601String(),
  'delivery_address': ?instance.deliveryAddress?.toJson(),
  'created_at': instance.createdAt.toIso8601String(),
};

const _$OrderStatusEnumEnumMap = {
  OrderStatusEnum.pendingPayment: 'pending_payment',
  OrderStatusEnum.paid: 'paid',
  OrderStatusEnum.shipped: 'shipped',
  OrderStatusEnum.delivered: 'delivered',
  OrderStatusEnum.cancelled: 'cancelled',
  OrderStatusEnum.refunded: 'refunded',
  OrderStatusEnum.partiallyRefunded: 'partially_refunded',
};

const _$OrderCargoOptionEnumEnumMap = {
  OrderCargoOptionEnum.aras: 'aras',
  OrderCargoOptionEnum.yurtici: 'yurtici',
  OrderCargoOptionEnum.surat: 'surat',
  OrderCargoOptionEnum.mng: 'mng',
  OrderCargoOptionEnum.hepsijet: 'hepsijet',
  OrderCargoOptionEnum.ptt: 'ptt',
};
