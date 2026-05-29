// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_promo_slot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CategoryPromoSlot _$CategoryPromoSlotFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CategoryPromoSlot',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const ['image_url', 'title', 'deep_link'],
        );
        final val = CategoryPromoSlot(
          imageUrl: $checkedConvert('image_url', (v) => v as String),
          title: $checkedConvert('title', (v) => v as String),
          deepLink: $checkedConvert('deep_link', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'imageUrl': 'image_url', 'deepLink': 'deep_link'},
    );

Map<String, dynamic> _$CategoryPromoSlotToJson(CategoryPromoSlot instance) =>
    <String, dynamic>{
      'image_url': instance.imageUrl,
      'title': instance.title,
      'deep_link': instance.deepLink,
    };
