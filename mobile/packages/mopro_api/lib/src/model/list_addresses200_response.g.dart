// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_addresses200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ListAddresses200Response _$ListAddresses200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ListAddresses200Response', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['data']);
  final val = ListAddresses200Response(
    data: $checkedConvert(
      'data',
      (v) => (v as List<dynamic>)
          .map((e) => Address.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$ListAddresses200ResponseToJson(
  ListAddresses200Response instance,
) => <String, dynamic>{'data': instance.data.map((e) => e.toJson()).toList()};
