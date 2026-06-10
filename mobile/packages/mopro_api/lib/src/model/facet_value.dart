//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'facet_value.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class FacetValue {
  /// Returns a new [FacetValue] instance.
  FacetValue({

    required  this.value,

    required  this.count,
  });

  @JsonKey(
    
    name: r'value',
    required: true,
    includeIfNull: false,
  )


  final String value;



      /// Distinct products in the category subtree carrying this value.
          // minimum: 0
  @JsonKey(
    
    name: r'count',
    required: true,
    includeIfNull: false,
  )


  final int count;





    @override
    bool operator ==(Object other) => identical(this, other) || other is FacetValue &&
      other.value == value &&
      other.count == count;

    @override
    int get hashCode =>
        value.hashCode +
        count.hashCode;

  factory FacetValue.fromJson(Map<String, dynamic> json) => _$FacetValueFromJson(json);

  Map<String, dynamic> toJson() => _$FacetValueToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

