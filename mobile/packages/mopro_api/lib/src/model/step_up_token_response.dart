//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'step_up_token_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class StepUpTokenResponse {
  /// Returns a new [StepUpTokenResponse] instance.
  StepUpTokenResponse({

    required  this.stepUpToken,

    required  this.expiresIn,
  });

      /// Bearer token with scope=high_sensitivity. Use as Authorization header.
  @JsonKey(
    
    name: r'step_up_token',
    required: true,
    includeIfNull: false,
  )


  final String stepUpToken;



      /// Seconds until step-up token expiry. Always 300 (5 min).
  @JsonKey(
    
    name: r'expires_in',
    required: true,
    includeIfNull: false,
  )


  final int expiresIn;





    @override
    bool operator ==(Object other) => identical(this, other) || other is StepUpTokenResponse &&
      other.stepUpToken == stepUpToken &&
      other.expiresIn == expiresIn;

    @override
    int get hashCode =>
        stepUpToken.hashCode +
        expiresIn.hashCode;

  factory StepUpTokenResponse.fromJson(Map<String, dynamic> json) => _$StepUpTokenResponseFromJson(json);

  Map<String, dynamic> toJson() => _$StepUpTokenResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

