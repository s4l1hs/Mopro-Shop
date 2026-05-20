//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:mopro_api/src/model/product_summary.dart';
import 'package:json_annotation/json_annotation.dart';

part 'recommendation.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Recommendation {
  /// Returns a new [Recommendation] instance.
  Recommendation({

     this.score,

    required  this.product,
  });

      /// Internal ranking score (opaque; may be omitted)
  @JsonKey(
    
    name: r'score',
    required: false,
    includeIfNull: false,
  )


  final double? score;



  @JsonKey(
    
    name: r'product',
    required: true,
    includeIfNull: false,
  )


  final ProductSummary product;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Recommendation &&
      other.score == score &&
      other.product == product;

    @override
    int get hashCode =>
        score.hashCode +
        product.hashCode;

  factory Recommendation.fromJson(Map<String, dynamic> json) => _$RecommendationFromJson(json);

  Map<String, dynamic> toJson() => _$RecommendationToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

