//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'pagination_meta.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PaginationMeta {
  /// Returns a new [PaginationMeta] instance.
  PaginationMeta({

    required  this.page,

    required  this.perPage,

    required  this.total,

    required  this.totalPages,
  });

          // minimum: 1
  @JsonKey(
    
    name: r'page',
    required: true,
    includeIfNull: false,
  )


  final int page;



          // minimum: 1
          // maximum: 100
  @JsonKey(
    
    name: r'per_page',
    required: true,
    includeIfNull: false,
  )


  final int perPage;



  @JsonKey(
    
    name: r'total',
    required: true,
    includeIfNull: false,
  )


  final int total;



          // minimum: 0
  @JsonKey(
    
    name: r'total_pages',
    required: true,
    includeIfNull: false,
  )


  final int totalPages;





    @override
    bool operator ==(Object other) => identical(this, other) || other is PaginationMeta &&
      other.page == page &&
      other.perPage == perPage &&
      other.total == total &&
      other.totalPages == totalPages;

    @override
    int get hashCode =>
        page.hashCode +
        perPage.hashCode +
        total.hashCode +
        totalPages.hashCode;

  factory PaginationMeta.fromJson(Map<String, dynamic> json) => _$PaginationMetaFromJson(json);

  Map<String, dynamic> toJson() => _$PaginationMetaToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

