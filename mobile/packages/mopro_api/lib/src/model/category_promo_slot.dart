//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'category_promo_slot.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CategoryPromoSlot {
  /// Returns a new [CategoryPromoSlot] instance.
  CategoryPromoSlot({

    required  this.imageUrl,

    required  this.title,

    required  this.deepLink,
  });

      /// 16:9 image URL. Mobile clients should treat as opaque.
  @JsonKey(
    
    name: r'image_url',
    required: true,
    includeIfNull: false,
  )


  final String imageUrl;



      /// 2-line clamp display title.
  @JsonKey(
    
    name: r'title',
    required: true,
    includeIfNull: false,
  )


  final String title;



      /// In-app deep link for the CTA button.
  @JsonKey(
    
    name: r'deep_link',
    required: true,
    includeIfNull: false,
  )


  final String deepLink;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CategoryPromoSlot &&
      other.imageUrl == imageUrl &&
      other.title == title &&
      other.deepLink == deepLink;

    @override
    int get hashCode =>
        imageUrl.hashCode +
        title.hashCode +
        deepLink.hashCode;

  factory CategoryPromoSlot.fromJson(Map<String, dynamic> json) => _$CategoryPromoSlotFromJson(json);

  Map<String, dynamic> toJson() => _$CategoryPromoSlotToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

