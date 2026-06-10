//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'brand_suggestion.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class BrandSuggestion {
  /// Returns a new [BrandSuggestion] instance.
  BrandSuggestion({

    required  this.name,

    required  this.productCount,
  });

      /// Brand name
  @JsonKey(
    
    name: r'name',
    required: true,
    includeIfNull: false,
  )


  final String name;



      /// Number of active products carrying this brand
  @JsonKey(
    
    name: r'product_count',
    required: true,
    includeIfNull: false,
  )


  final int productCount;





    @override
    bool operator ==(Object other) => identical(this, other) || other is BrandSuggestion &&
      other.name == name &&
      other.productCount == productCount;

    @override
    int get hashCode =>
        name.hashCode +
        productCount.hashCode;

  factory BrandSuggestion.fromJson(Map<String, dynamic> json) => _$BrandSuggestionFromJson(json);

  Map<String, dynamic> toJson() => _$BrandSuggestionToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

