// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'suggest_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SuggestResponse _$SuggestResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SuggestResponse', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['brands', 'products']);
      final val = SuggestResponse(
        brands: $checkedConvert(
          'brands',
          (v) => (v as List<dynamic>)
              .map((e) => BrandSuggestion.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        products: $checkedConvert(
          'products',
          (v) => (v as List<dynamic>)
              .map((e) => ProductSummary.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$SuggestResponseToJson(SuggestResponse instance) =>
    <String, dynamic>{
      'brands': instance.brands.map((e) => e.toJson()).toList(),
      'products': instance.products.map((e) => e.toJson()).toList(),
    };
