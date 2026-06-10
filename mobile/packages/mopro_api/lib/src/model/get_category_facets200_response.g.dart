// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_category_facets200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetCategoryFacets200Response _$GetCategoryFacets200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GetCategoryFacets200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['facets']);
  final val = GetCategoryFacets200Response(
    facets: $checkedConvert(
      'facets',
      (v) => (v as List<dynamic>)
          .map((e) => Facet.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$GetCategoryFacets200ResponseToJson(
  GetCategoryFacets200Response instance,
) => <String, dynamic>{
  'facets': instance.facets.map((e) => e.toJson()).toList(),
};
