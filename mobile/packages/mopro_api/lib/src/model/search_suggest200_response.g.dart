// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_suggest200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SearchSuggest200Response _$SearchSuggest200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('SearchSuggest200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['suggestions']);
  final val = SearchSuggest200Response(
    suggestions: $checkedConvert(
      'suggestions',
      (v) => (v as List<dynamic>).map((e) => e as String).toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$SearchSuggest200ResponseToJson(
  SearchSuggest200Response instance,
) => <String, dynamic>{'suggestions': instance.suggestions};
