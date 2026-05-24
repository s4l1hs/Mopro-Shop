// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'refresh_token_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RefreshTokenRequest _$RefreshTokenRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RefreshTokenRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['refresh_token']);
      final val = RefreshTokenRequest(
        refreshToken: $checkedConvert('refresh_token', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'refreshToken': 'refresh_token'});

Map<String, dynamic> _$RefreshTokenRequestToJson(
  RefreshTokenRequest instance,
) => <String, dynamic>{'refresh_token': instance.refreshToken};
