//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'register_device_request.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RegisterDeviceRequest {
  /// Returns a new [RegisterDeviceRequest] instance.
  RegisterDeviceRequest({

    required  this.fcmToken,

    required  this.deviceModel,

    required  this.osVersion,
  });

  @JsonKey(
    
    name: r'fcm_token',
    required: true,
    includeIfNull: false,
  )


  final String fcmToken;



  @JsonKey(
    
    name: r'device_model',
    required: true,
    includeIfNull: false,
  )


  final String deviceModel;



  @JsonKey(
    
    name: r'os_version',
    required: true,
    includeIfNull: false,
  )


  final String osVersion;





    @override
    bool operator ==(Object other) => identical(this, other) || other is RegisterDeviceRequest &&
      other.fcmToken == fcmToken &&
      other.deviceModel == deviceModel &&
      other.osVersion == osVersion;

    @override
    int get hashCode =>
        fcmToken.hashCode +
        deviceModel.hashCode +
        osVersion.hashCode;

  factory RegisterDeviceRequest.fromJson(Map<String, dynamic> json) => _$RegisterDeviceRequestFromJson(json);

  Map<String, dynamic> toJson() => _$RegisterDeviceRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

