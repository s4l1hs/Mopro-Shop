//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/recommendation.dart';
import 'package:json_annotation/json_annotation.dart';

part 'list_recommendations200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ListRecommendations200Response {
  /// Returns a new [ListRecommendations200Response] instance.
  ListRecommendations200Response({

    required  this.data,
  });

  @JsonKey(
    
    name: r'data',
    required: true,
    includeIfNull: false,
  )


  final List<Recommendation> data;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ListRecommendations200Response &&
      other.data == data;

    @override
    int get hashCode =>
        data.hashCode;

  factory ListRecommendations200Response.fromJson(Map<String, dynamic> json) => _$ListRecommendations200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ListRecommendations200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

