// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_returns200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListReturns200Response _$ListReturns200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListReturns200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data']);
  final val = ListReturns200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => ModelReturn.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListReturns200ResponseToJson(
  ListReturns200Response instance,
) => <String, dynamic>{'data': instance.data.map((e) => e.toJson()).toList()};
