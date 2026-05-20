//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'banner.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Banner {
  /// Returns a new [Banner] instance.
  Banner({

    required  this.id,

    required  this.placement,

    required  this.imageUrl,

    required  this.actionType,

     this.actionUrl,

     this.expiresAt,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



  @JsonKey(
    
    name: r'placement',
    required: true,
    includeIfNull: false,
  )


  final String placement;



  @JsonKey(
    
    name: r'image_url',
    required: true,
    includeIfNull: false,
  )


  final String imageUrl;



  @JsonKey(
    
    name: r'action_type',
    required: true,
    includeIfNull: false,
  )


  final BannerActionTypeEnum actionType;



      /// Deep link path or external URL; null when action_type=none
  @JsonKey(
    
    name: r'action_url',
    required: false,
    includeIfNull: false,
  )


  final String? actionUrl;



  @JsonKey(
    
    name: r'expires_at',
    required: false,
    includeIfNull: false,
  )


  final DateTime? expiresAt;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Banner &&
      other.id == id &&
      other.placement == placement &&
      other.imageUrl == imageUrl &&
      other.actionType == actionType &&
      other.actionUrl == actionUrl &&
      other.expiresAt == expiresAt;

    @override
    int get hashCode =>
        id.hashCode +
        placement.hashCode +
        imageUrl.hashCode +
        actionType.hashCode +
        actionUrl.hashCode +
        expiresAt.hashCode;

  factory Banner.fromJson(Map<String, dynamic> json) => _$BannerFromJson(json);

  Map<String, dynamic> toJson() => _$BannerToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}


enum BannerActionTypeEnum {
@JsonValue(r'deeplink')
deeplink(r'deeplink'),
@JsonValue(r'external')
external_(r'external'),
@JsonValue(r'none')
none(r'none');

const BannerActionTypeEnum(this.value);

final String value;

@override
String toString() => value;
}


