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
  });

      /// Turkish mobile number in E.164 format. Must start with +905.
  @JsonKey(
    
    name: r'phone',
    required: true,
    includeIfNull: false,
  )


  final String phone;





    @override
    bool operator ==(Object other) => identical(this, other) || other is RequestOtpRequest &&
      other.phone == phone;

    @override
    int get hashCode =>
        phone.hashCode;

  factory RequestOtpRequest.fromJson(Map<String, dynamic> json) => _$RequestOtpRequestFromJson(json);

  Map<String, dynamic> toJson() => _$RequestOtpRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

