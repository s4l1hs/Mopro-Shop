// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_pair.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TokenPair _$TokenPairFromJson(Map<String, dynamic> json) => $checkedCreate(
  'TokenPair',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'access_token',
        'token_type',
        'expires_in',
        'refresh_token',
        'refresh_expires_at',
      ],
    );
    final val = TokenPair(
      accessToken: $checkedConvert('access_token', (v) => v as String),
      tokenType: $checkedConvert(
        'token_type',
        (v) => $enumDecode(_$TokenPairTokenTypeEnumEnumMap, v),
      ),
      expiresIn: $checkedConvert('expires_in', (v) => (v as num).toInt()),
      refreshToken: $checkedConvert('refresh_token', (v) => v as String),
      refreshExpiresAt: $checkedConvert(
        'refresh_expires_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'accessToken': 'access_token',
    'tokenType': 'token_type',
    'expiresIn': 'expires_in',
    'refreshToken': 'refresh_token',
    'refreshExpiresAt': 'refresh_expires_at',
  },
);

Map<String, dynamic> _$TokenPairToJson(TokenPair instance) => <String, dynamic>{
  'access_token': instance.accessToken,
  'token_type': _$TokenPairTokenTypeEnumEnumMap[instance.tokenType]!,
  'expires_in': instance.expiresIn,
  'refresh_token': instance.refreshToken,
  'refresh_expires_at': instance.refreshExpiresAt.toIso8601String(),
};

const _$TokenPairTokenTypeEnumEnumMap = {
  TokenPairTokenTypeEnum.bearer: 'Bearer',
};
