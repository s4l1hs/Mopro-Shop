// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'facet.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Facet _$FacetFromJson(Map<String, dynamic> json) =>
    $checkedCreate('Facet', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['slug', 'name', 'values']);
      final val = Facet(
        slug: $checkedConvert('slug', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        values: $checkedConvert(
          'values',
          (v) => (v as List<dynamic>)
              .map((e) => FacetValue.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$FacetToJson(Facet instance) => <String, dynamic>{
  'slug': instance.slug,
  'name': instance.name,
  'values': instance.values.map((e) => e.toJson()).toList(),
};
