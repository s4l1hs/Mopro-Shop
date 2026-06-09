// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'brand_suggestion.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BrandSuggestion _$BrandSuggestionFromJson(Map<String, dynamic> json) =>
    $checkedCreate('BrandSuggestion', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['name', 'product_count']);
      final val = BrandSuggestion(
        name: $checkedConvert('name', (v) => v as String),
        productCount: $checkedConvert(
          'product_count',
          (v) => (v as num).toInt(),
        ),
      );
      return val;
    }, fieldKeyMap: const {'productCount': 'product_count'});

Map<String, dynamic> _$BrandSuggestionToJson(BrandSuggestion instance) =>
    <String, dynamic>{
      'name': instance.name,
      'product_count': instance.productCount,
    };
