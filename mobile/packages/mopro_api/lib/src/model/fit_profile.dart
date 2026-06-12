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
      other.fitPref == fitPref;

    @override
    int get hashCode =>
        chestMm.hashCode +
        waistMm.hashCode +
        hipMm.hashCode +
        inseamMm.hashCode +
        heightMm.hashCode +
        fitPref.hashCode;

  factory FitProfile.fromJson(Map<String, dynamic> json) => _$FitProfileFromJson(json);

  Map<String, dynamic> toJson() => _$FitProfileToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

