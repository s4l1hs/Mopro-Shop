//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'size_recommendation.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SizeRecommendation {
  /// Returns a new [SizeRecommendation] instance.
  SizeRecommendation({

    required  this.status,

     this.garmentType,

     this.size,

     this.signal,

     this.betweenLower,

     this.betweenUpper,

     this.missing,

     this.confidence,

     this.estimated,

    required  this.chartApproximate,
  });

      /// ok | no_profile | incomplete_profile | no_chart
  @JsonKey(
    
    name: r'status',
    required: true,
    includeIfNull: false,
  )


  final String status;



      /// top | bottom | dress | skirt | outerwear (chart key).
  @JsonKey(
    
    name: r'garment_type',
    required: false,
    includeIfNull: false,
  )


  final String? garmentType;



  @JsonKey(
    
    name: r'size',
    required: false,
    includeIfNull: false,
  )


  final String? size;



      /// true_to_size | between | size_up | size_down
  @JsonKey(
    
    name: r'signal',
    required: false,
    includeIfNull: false,
  )


  final String? signal;



  @JsonKey(
    
    name: r'between_lower',
    required: false,
    includeIfNull: false,
  )


  final String? betweenLower;



  @JsonKey(
    
    name: r'between_upper',
    required: false,
    includeIfNull: false,
  )


  final String? betweenUpper;



  @JsonKey(
    
    name: r'missing',
    required: false,
    includeIfNull: false,
  )


  final List<String>? missing;



      /// detailed (every relevant measurement was a real profile value) | basic (>=1 was estimated from height/weight/gender → show the approximate warning). Empty for non-ok statuses. 
  @JsonKey(
    
    name: r'confidence',
    required: false,
    includeIfNull: false,
  )


  final String? confidence;



      /// Relevant measurements synthesized from height/weight/gender.
  @JsonKey(
    
    name: r'estimated',
    required: false,
    includeIfNull: false,
  )


  final List<String>? estimated;



  @JsonKey(
    
    name: r'chart_approximate',
    required: true,
    includeIfNull: false,
  )


  final bool chartApproximate;





    @override
    bool operator ==(Object other) => identical(this, other) || other is SizeRecommendation &&
      other.status == status &&
      other.garmentType == garmentType &&
      other.size == size &&
      other.signal == signal &&
      other.betweenLower == betweenLower &&
      other.betweenUpper == betweenUpper &&
      other.missing == missing &&
      other.confidence == confidence &&
      other.estimated == estimated &&
      other.chartApproximate == chartApproximate;

    @override
    int get hashCode =>
        status.hashCode +
        garmentType.hashCode +
        size.hashCode +
        signal.hashCode +
        betweenLower.hashCode +
        betweenUpper.hashCode +
        missing.hashCode +
        confidence.hashCode +
        estimated.hashCode +
        chartApproximate.hashCode;

  factory SizeRecommendation.fromJson(Map<String, dynamic> json) => _$SizeRecommendationFromJson(json);

  Map<String, dynamic> toJson() => _$SizeRecommendationToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

