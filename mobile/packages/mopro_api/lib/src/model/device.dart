//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'device.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Device {
  /// Returns a new [Device] instance.
  Device({

    required  this.id,

    required  this.fcmToken,

    required  this.deviceModel,

    required  this.osVersion,

    required  this.createdAt,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



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



  @JsonKey(
    
    name: r'created_at',
    required: true,
    includeIfNull: false,
  )


  final DateTime createdAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Device &&
      other.id == id &&
      other.fcmToken == fcmToken &&
      other.deviceModel == deviceModel &&
      other.osVersion == osVersion &&
      other.createdAt == createdAt;

    @override
    int get hashCode =>
        id.hashCode +
        fcmToken.hashCode +
        deviceModel.hashCode +
        osVersion.hashCode +
        createdAt.hashCode;

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

