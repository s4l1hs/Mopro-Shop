//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'request_otp_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RequestOtpRequest {
  /// Returns a new [RequestOtpRequest] instance.
  RequestOtpRequest({

    required  this.phone,

     this.purpose = RequestOtpRequestPurposeEnum.login,
  });

      /// Turkish mobile number in E.164 format. Must start with +905.
  @JsonKey(
    
    name: r'phone',
    required: true,
    includeIfNull: false,
  )


  final String phone;



      /// OTP purpose. Use `login` for initial authentication (default). Use `step_up` only if you need a step-up OTP outside the authenticated step-up flow (`POST /auth/step-up/request`). Most clients should omit this field and rely on the default. 
  @JsonKey(
    defaultValue: 'login',
    name: r'purpose',
    required: false,
    includeIfNull: false,
  )


  final RequestOtpRequestPurposeEnum? purpose;





    @override
    bool operator ==(Object other) => identical(this, other) || other is RequestOtpRequest &&
      other.phone == phone &&
      other.purpose == purpose;

    @override
    int get hashCode =>
        phone.hashCode +
        purpose.hashCode;

  factory RequestOtpRequest.fromJson(Map<String, dynamic> json) => _$RequestOtpRequestFromJson(json);

  Map<String, dynamic> toJson() => _$RequestOtpRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

/// OTP purpose. Use `login` for initial authentication (default). Use `step_up` only if you need a step-up OTP outside the authenticated step-up flow (`POST /auth/step-up/request`). Most clients should omit this field and rely on the default. 
enum RequestOtpRequestPurposeEnum {
    /// OTP purpose. Use `login` for initial authentication (default). Use `step_up` only if you need a step-up OTP outside the authenticated step-up flow (`POST /auth/step-up/request`). Most clients should omit this field and rely on the default. 
@JsonValue(r'login')
login(r'login'),
    /// OTP purpose. Use `login` for initial authentication (default). Use `step_up` only if you need a step-up OTP outside the authenticated step-up flow (`POST /auth/step-up/request`). Most clients should omit this field and rely on the default. 
@JsonValue(r'step_up')
stepUp(r'step_up');

const RequestOtpRequestPurposeEnum(this.value);

final String value;

@override
String toString() => value;
}


