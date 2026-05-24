// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_trending200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SearchTrending200Response _$SearchTrending200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('SearchTrending200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['terms']);
  final val = SearchTrending200Response(
    terms: $checkedConvert(
      'terms',
      (v) => (v as List<dynamic>).map((e) => e as String).toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$SearchTrending200ResponseToJson(
  SearchTrending200Response instance,
) => <String, dynamic>{'terms': instance.terms};
