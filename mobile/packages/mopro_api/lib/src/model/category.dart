//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'category.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class Category {
  /// Returns a new [Category] instance.
  Category({

    required  this.id,

    required  this.name,

    required  this.slug,

     this.parentId,

     this.iconUrl,

    required  this.commissionPctBps,
  });

  @JsonKey(
    
    name: r'id',
    required: true,
    includeIfNull: false,
  )


  final int id;



      /// Locale-resolved category name
  @JsonKey(
    
    name: r'name',
    required: true,
    includeIfNull: false,
  )


  final String name;



  @JsonKey(
    
    name: r'slug',
    required: true,
    includeIfNull: false,
  )


  final String slug;



  @JsonKey(
    
    name: r'parent_id',
    required: false,
    includeIfNull: false,
  )


  final int? parentId;



  @JsonKey(
    
    name: r'icon_url',
    required: false,
    includeIfNull: false,
  )


  final String? iconUrl;



      /// Commission rate in basis points (e.g. 1500 = 15%)
  @JsonKey(
    
    name: r'commission_pct_bps',
    required: true,
    includeIfNull: false,
  )


  final int commissionPctBps;





    @override
    bool operator ==(Object other) => identical(this, other) || other is Category &&
      other.id == id &&
      other.name == name &&
      other.slug == slug &&
      other.parentId == parentId &&
      other.iconUrl == iconUrl &&
      other.commissionPctBps == commissionPctBps;

    @override
    int get hashCode =>
        id.hashCode +
        name.hashCode +
        slug.hashCode +
        parentId.hashCode +
        iconUrl.hashCode +
        commissionPctBps.hashCode;

  factory Category.fromJson(Map<String, dynamic> json) => _$CategoryFromJson(json);

  Map<String, dynamic> toJson() => _$CategoryToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

