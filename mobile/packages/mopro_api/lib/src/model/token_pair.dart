//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'token_pair.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class TokenPair {
  /// Returns a new [TokenPair] instance.
  TokenPair({

    required  this.accessToken,

    required  this.tokenType,

    required  this.expiresIn,

    required  this.refreshToken,

    required  this.refreshExpiresAt,
  });

  @JsonKey(
    
    name: r'access_token',
    required: true,
    includeIfNull: false,
  )


  final String accessToken;



  @JsonKey(
    
    name: r'token_type',
    required: true,
    includeIfNull: false,
  )


  final TokenPairTokenTypeEnum tokenType;



      /// Seconds until access token expiry. Always 900 (15 min).
  @JsonKey(
    
    name: r'expires_in',
    required: true,
    includeIfNull: false,
  )


  final int expiresIn;



  @JsonKey(
    
    name: r'refresh_token',
    required: true,
    includeIfNull: false,
  )


  final String refreshToken;



  @JsonKey(
    
    name: r'refresh_expires_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime refreshExpiresAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is TokenPair &&
      other.accessToken == accessToken &&
      other.tokenType == tokenType &&
      other.expiresIn == expiresIn &&
      other.refreshToken == refreshToken &&
      other.refreshExpiresAt == refreshExpiresAt;

    @override
    int get hashCode =>
        accessToken.hashCode +
        tokenType.hashCode +
        expiresIn.hashCode +
        refreshToken.hashCode +
        refreshExpiresAt.hashCode;

  factory TokenPair.fromJson(Map<String, dynamic> json) => _$TokenPairFromJson(json);

  Map<String, dynamic> toJson() => _$TokenPairToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum TokenPairTokenTypeEnum {
@JsonValue(r'Bearer')
bearer(r'Bearer');

const TokenPairTokenTypeEnum(this.value);

final String value;

@override
String toString() => value;
}


