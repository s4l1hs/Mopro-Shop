// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_me_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeleteMeRequest _$DeleteMeRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DeleteMeRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['reason']);
      final val = DeleteMeRequest(
        reason: $checkedConvert(
          'reason',
          (v) => $enumDecode(_$DeleteMeRequestReasonEnumEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$DeleteMeRequestToJson(DeleteMeRequest instance) =>
    <String, dynamic>{
      'reason': _$DeleteMeRequestReasonEnumEnumMap[instance.reason]!,
    };

const _$DeleteMeRequestReasonEnumEnumMap = {
  DeleteMeRequestReasonEnum.noLongerNeeded: 'no_longer_needed',
  DeleteMeRequestReasonEnum.privacyConcern: 'privacy_concern',
  DeleteMeRequestReasonEnum.badExperience: 'bad_experience',
  DeleteMeRequestReasonEnum.switchingPlatform: 'switching_platform',
  DeleteMeRequestReasonEnum.other: 'other',
};
