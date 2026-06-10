//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/facet.dart';
import 'package:json_annotation/json_annotation.dart';

part 'get_category_facets200_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GetCategoryFacets200Response {
  /// Returns a new [GetCategoryFacets200Response] instance.
  GetCategoryFacets200Response({

    required  this.facets,
  });

  @JsonKey(
    
    name: r'facets',
    required: true,
    includeIfNull: false,
  )


  final List<Facet> facets;





    @override
    bool operator ==(Object other) => identical(this, other) || other is GetCategoryFacets200Response &&
      other.facets == facets;

    @override
    int get hashCode =>
        facets.hashCode;

  factory GetCategoryFacets200Response.fromJson(Map<String, dynamic> json) => _$GetCategoryFacets200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GetCategoryFacets200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

