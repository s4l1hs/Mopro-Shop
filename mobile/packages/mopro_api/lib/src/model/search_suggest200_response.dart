//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'search_suggest200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SearchSuggest200Response {
  /// Returns a new [SearchSuggest200Response] instance.
  SearchSuggest200Response({

    required  this.suggestions,
  });

  @JsonKey(
    
    name: r'suggestions',
    required: true,
    includeIfNull: false,
  )


  final List<String> suggestions;





    @override
    bool operator ==(Object other) => identical(this, other) || other is SearchSuggest200Response &&
      other.suggestions == suggestions;

    @override
    int get hashCode =>
        suggestions.hashCode;

  factory SearchSuggest200Response.fromJson(Map<String, dynamic> json) => _$SearchSuggest200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SearchSuggest200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

