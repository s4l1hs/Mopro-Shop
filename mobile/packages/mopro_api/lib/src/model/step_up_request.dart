//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'step_up_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class StepUpRequest {
  /// Returns a new [StepUpRequest] instance.
  StepUpRequest({

    required  this.otpCode,
  });

  @JsonKey(
    
    name: r'otp_code',
    required: true,
    includeIfNull: false,
  )


  final String otpCode;





    @override
    bool operator ==(Object other) => identical(this, other) || other is StepUpRequest &&
      other.otpCode == otpCode;

    @override
    int get hashCode =>
        otpCode.hashCode;

  factory StepUpRequest.fromJson(Map<String, dynamic> json) => _$StepUpRequestFromJson(json);

  Map<String, dynamic> toJson() => _$StepUpRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

