//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'product_attribute.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProductAttribute {
  /// Returns a new [ProductAttribute] instance.
  ProductAttribute({

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


  final List<String> values;





    @override
    bool operator ==(Object other) => identical(this, other) || other is ProductAttribute &&
      other.slug == slug &&
      other.name == name &&
      other.values == values;

    @override
    int get hashCode =>
        slug.hashCode +
        name.hashCode +
        values.hashCode;

  factory ProductAttribute.fromJson(Map<String, dynamic> json) => _$ProductAttributeFromJson(json);

  Map<String, dynamic> toJson() => _$ProductAttributeToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

