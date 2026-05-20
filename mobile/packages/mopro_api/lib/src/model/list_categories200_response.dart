//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/category.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_categories200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListCategories200Response {
  /// Returns a new [ListCategories200Response] instance.
  ListCategories200Response({

    required  this.data,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<Category> data;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListCategories200Response &&
      other.data == data;

    @override
    int get hashCode =>
        data.hashCode;

  factory ListCategories200Response.fromJson(Map<String, dynamic> json) => _$ListCategories200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListCategories200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

