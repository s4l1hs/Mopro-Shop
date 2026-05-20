//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/banner.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_banners200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListBanners200Response {
  /// Returns a new [ListBanners200Response] instance.
  ListBanners200Response({

    required  this.data,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<Banner> data;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListBanners200Response &&
      other.data == data;

    @override
    int get hashCode =>
        data.hashCode;

  factory ListBanners200Response.fromJson(Map<String, dynamic> json) => _$ListBanners200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListBanners200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

