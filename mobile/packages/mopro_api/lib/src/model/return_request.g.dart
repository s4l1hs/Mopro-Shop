// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'return_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReturnRequest _$ReturnRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReturnRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['reason']);
      final val = ReturnRequest(
        reason: $checkedConvert(
          'reason',
          (v) => $enumDecode(_$ReturnRequestReasonEnumEnumMap, v),
        ),
        description: $checkedConvert('description', (v) => v as String?),
        items: $checkedConvert(
          'items',
          (v) => (v as List<dynamic>?)
              ?.map(
                (e) =>
                    ReturnRequestItemsInner.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
        ),
        photoKeys: $checkedConvert(
          'photo_keys',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
        ),
      );
      return val;
    }, fieldKeyMap: const {'photoKeys': 'photo_keys'});

Map<String, dynamic> _$ReturnRequestToJson(ReturnRequest instance) =>
    <String, dynamic>{
      'reason': _$ReturnRequestReasonEnumEnumMap[instance.reason]!,
      'description': ?instance.description,
      'items': ?instance.items?.map((e) => e.toJson()).toList(),
      'photo_keys': ?instance.photoKeys,
    };

const _$ReturnRequestReasonEnumEnumMap = {
  ReturnRequestReasonEnum.wrongProduct: 'wrong_product',
  ReturnRequestReasonEnum.notAsDescribed: 'not_as_described',
  ReturnRequestReasonEnum.damaged: 'damaged',
  ReturnRequestReasonEnum.sizeIssue: 'size_issue',
  ReturnRequestReasonEnum.changedMind: 'changed_mind',
  ReturnRequestReasonEnum.other: 'other',
};
