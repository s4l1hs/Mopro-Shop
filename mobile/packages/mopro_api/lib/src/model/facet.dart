//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/facet_value.dart';
import 'package:json_annotation/json_annotation.dart';

part 'facet.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Facet {
  /// Returns a new [Facet] instance.
  Facet({

    required  this.slug,

    required  this.name,

    required  this.values,
  });

  @JsonKey(
    
    name: r'slug',
    required: true,
    includeIfNull: false,
  )


  final String slug;



      /// Locale-resolved attribute name (name_tr/name_en).
  @JsonKey(
    
    name: r'name',
    required: true,
    includeIfNull: false,
  )


  final String name;



  @JsonKey(
    
    name: r'values',
    required: true,
    includeIfNull: false,
  )


  final List<FacetValue> values;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Facet &&
      other.slug == slug &&
      other.name == name &&
      other.values == values;

    @override
    int get hashCode =>
        slug.hashCode +
        name.hashCode +
        values.hashCode;

  factory Facet.fromJson(Map<String, dynamic> json) => _$FacetFromJson(json);

  Map<String, dynamic> toJson() => _$FacetToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

