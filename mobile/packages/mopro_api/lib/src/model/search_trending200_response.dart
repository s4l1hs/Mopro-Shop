//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'search_trending200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SearchTrending200Response {
  /// Returns a new [SearchTrending200Response] instance.
  SearchTrending200Response({

    required  this.terms,
  });

  @JsonKey(
    
    name: r'terms',
    required: true,
    includeIfNull: false,
  )


  final List<String> terms;





    @override
    bool operator ==(Object other) => identical(this, other) || other is SearchTrending200Response &&
      other.terms == terms;

    @override
    int get hashCode =>
        terms.hashCode;

  factory SearchTrending200Response.fromJson(Map<String, dynamic> json) => _$SearchTrending200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SearchTrending200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

