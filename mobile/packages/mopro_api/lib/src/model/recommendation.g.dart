// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recommendation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Recommendation _$RecommendationFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Recommendation', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['product']);
      final val = Recommendation(
        score: $checkedConvert('score', (v) => (v as num?)?.toDouble()),
        product: $checkedConvert(
          'product',
          (v) => ProductSummary.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$RecommendationToJson(Recommendation instance) =>
    <String, dynamic>{
      'score': ?instance.score,
      'product': instance.product.toJson(),
    };
