//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'verify_otp_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class VerifyOtpRequest {
  /// Returns a new [VerifyOtpRequest] instance.
  VerifyOtpRequest({

    required  this.phone,

    required  this.code,

     this.purpose = const VerifyOtpRequestPurposeEnum._('login'),
  });

  @JsonKey(
    
    name: r'phone',
    required: true,
    includeIfNull: false,
  )


  final String phone;



  @JsonKey(
    
    name: r'code',
    required: true,
    includeIfNull: false,
  )


  final String code;



      /// Must match the purpose used in the corresponding /otp/request call. Defaults to `login`.
  @JsonKey(
    defaultValue: 'login',
    name: r'purpose',
    required: false,
    includeIfNull: false,
  )


  final VerifyOtpRequestPurposeEnum? purpose;





    @override
    bool operator ==(Object other) => identical(this, other) || other is VerifyOtpRequest &&
      other.phone == phone &&
      other.code == code &&
      other.purpose == purpose;

    @override
    int get hashCode =>
        phone.hashCode +
        code.hashCode +
        purpose.hashCode;

  factory VerifyOtpRequest.fromJson(Map<String, dynamic> json) => _$VerifyOtpRequestFromJson(json);

  Map<String, dynamic> toJson() => _$VerifyOtpRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

/// Must match the purpose used in the corresponding /otp/request call. Defaults to `login`.
enum VerifyOtpRequestPurposeEnum {
    /// Must match the purpose used in the corresponding /otp/request call. Defaults to `login`.
@JsonValue(r'login')
login(r'login'),
    /// Must match the purpose used in the corresponding /otp/request call. Defaults to `login`.
@JsonValue(r'step_up')
stepUp(r'step_up');

const VerifyOtpRequestPurposeEnum(this.value);

final String value;

@override
String toString() => value;
}


