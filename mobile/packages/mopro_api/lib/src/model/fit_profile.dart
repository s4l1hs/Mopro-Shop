//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'fit_profile.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FitProfile {
  /// Returns a new [FitProfile] instance.
  FitProfile({

     this.chestMm,

     this.waistMm,

     this.hipMm,

     this.inseamMm,

     this.heightMm,

     this.weightG,

     this.gender,

    required  this.fitPref,
  });

  @JsonKey(
    
    name: r'chest_mm',
    required: false,
    includeIfNull: false,
  )


  final int? chestMm;



  @JsonKey(
    
    name: r'waist_mm',
    required: false,
    includeIfNull: false,
  )


  final int? waistMm;



  @JsonKey(
    
    name: r'hip_mm',
    required: false,
    includeIfNull: false,
  )


  final int? hipMm;



  @JsonKey(
    
    name: r'inseam_mm',
    required: false,
    includeIfNull: false,
  )


  final int? inseamMm;



  @JsonKey(
    
    name: r'height_mm',
    required: false,
    includeIfNull: false,
  )


  final int? heightMm;



      /// Weight in grams (basic-estimation input; encrypted at rest).
  @JsonKey(
    
    name: r'weight_g',
    required: false,
    includeIfNull: false,
  )


  final int? weightG;



      /// female | male | unspecified (basic-estimation input, NOT a measurement). unspecified disables basic estimation for the user. 
  @JsonKey(
    
    name: r'gender',
    required: false,
    includeIfNull: false,
  )


  final String? gender;



      /// regular | loose | tight (between-sizes tiebreak).
  @JsonKey(
    
    name: r'fit_pref',
    required: true,
    includeIfNull: false,
  )


  final String fitPref;





    @override
    bool operator ==(Object other) => identical(this, other) || other is FitProfile &&
      other.chestMm == chestMm &&
      other.waistMm == waistMm &&
      other.hipMm == hipMm &&
      other.inseamMm == inseamMm &&
      other.heightMm == heightMm &&
      other.weightG == weightG &&
      other.gender == gender &&
      other.fitPref == fitPref;

    @override
    int get hashCode =>
        chestMm.hashCode +
        waistMm.hashCode +
        hipMm.hashCode +
        inseamMm.hashCode +
        heightMm.hashCode +
        weightG.hashCode +
        gender.hashCode +
        fitPref.hashCode;

  factory FitProfile.fromJson(Map<String, dynamic> json) => _$FitProfileFromJson(json);

  Map<String, dynamic> toJson() => _$FitProfileToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

