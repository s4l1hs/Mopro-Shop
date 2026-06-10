//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/brand_suggestion.dart';
import 'package:mopro_api/src/model/product_summary.dart';
import 'package:json_annotation/json_annotation.dart';

part 'suggest_response.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SuggestResponse {
  /// Returns a new [SuggestResponse] instance.
  SuggestResponse({

    required  this.brands,

    required  this.products,
  });

      /// Matching brands, ordered by active-product count desc
  @JsonKey(
    
    name: r'brands',
    required: true,
    includeIfNull: false,
  )


  final List<BrandSuggestion> brands;



      /// Top matching product summaries (route to PDP)
  @JsonKey(
    
    name: r'products',
    required: true,
    includeIfNull: false,
  )


  final List<ProductSummary> products;





    @override
    bool operator ==(Object other) => identical(this, other) || other is SuggestResponse &&
      other.brands == brands &&
      other.products == products;

    @override
    int get hashCode =>
        brands.hashCode +
        products.hashCode;

  factory SuggestResponse.fromJson(Map<String, dynamic> json) => _$SuggestResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SuggestResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

