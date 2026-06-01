// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seller_binding.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SellerBinding _$SellerBindingFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'SellerBinding',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'seller_id',
            'seller_slug',
            'seller_name',
            'role',
          ],
        );
        final val = SellerBinding(
          sellerId: $checkedConvert('seller_id', (v) => (v as num).toInt()),
          sellerSlug: $checkedConvert('seller_slug', (v) => v as String),
          sellerName: $checkedConvert('seller_name', (v) => v as String),
          role: $checkedConvert(
            'role',
            (v) => $enumDecode(_$SellerBindingRoleEnumEnumMap, v),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'sellerId': 'seller_id',
        'sellerSlug': 'seller_slug',
        'sellerName': 'seller_name',
      },
    );

Map<String, dynamic> _$SellerBindingToJson(SellerBinding instance) =>
    <String, dynamic>{
      'seller_id': instance.sellerId,
      'seller_slug': instance.sellerSlug,
      'seller_name': instance.sellerName,
      'role': _$SellerBindingRoleEnumEnumMap[instance.role]!,
    };

const _$SellerBindingRoleEnumEnumMap = {
  SellerBindingRoleEnum.owner: 'owner',
  SellerBindingRoleEnum.staff: 'staff',
};
