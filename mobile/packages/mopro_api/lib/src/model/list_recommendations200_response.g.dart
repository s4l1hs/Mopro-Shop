// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_recommendations200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListRecommendations200Response _$ListRecommendations200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListRecommendations200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data']);
  final val = ListRecommendations200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => Recommendation.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListRecommendations200ResponseToJson(
  ListRecommendations200Response instance,
) => <String, dynamic>{'data': instance.data.map((e) => e.toJson()).toList()};
