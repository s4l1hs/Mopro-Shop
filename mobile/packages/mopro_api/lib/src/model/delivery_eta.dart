//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'delivery_eta.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DeliveryEta {
  /// Returns a new [DeliveryEta] instance.
  DeliveryEta({

    required  this.minDays,

    required  this.maxDays,

    required  this.confident,

     this.dispatchCity,
  });

      /// Lower bound of the transit business-day estimate.
          // minimum: 0
  @JsonKey(
    
    name: r'min_days',
    required: true,
    includeIfNull: false,
  )


  final int minDays;



      /// Upper bound of the transit business-day estimate.
          // minimum: 0
  @JsonKey(
    
    name: r'max_days',
    required: true,
    includeIfNull: false,
  )


  final int maxDays;



      /// true when derived from a concrete origin×destination transit row; false when it is the conservative national fallback (unknown origin or destination, e.g. a guest with no address). 
  @JsonKey(
    
    name: r'confident',
    required: true,
    includeIfNull: false,
  )


  final bool confident;



      /// Normalized key of the seller's dispatch city, for an optional \"{city}'dan gönderilir\" line. Omitted when the origin is unknown. 
  @JsonKey(
    
    name: r'dispatch_city',
    required: false,
    includeIfNull: false,
  )


  final String? dispatchCity;





    @override
    bool operator ==(Object other) => identical(this, other) || other is DeliveryEta &&
      other.minDays == minDays &&
      other.maxDays == maxDays &&
      other.confident == confident &&
      other.dispatchCity == dispatchCity;

    @override
    int get hashCode =>
        minDays.hashCode +
        maxDays.hashCode +
        confident.hashCode +
        dispatchCity.hashCode;

  factory DeliveryEta.fromJson(Map<String, dynamic> json) => _$DeliveryEtaFromJson(json);

  Map<String, dynamic> toJson() => _$DeliveryEtaToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

