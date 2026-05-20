//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'cursor_pagination_meta.g.dart';


@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CursorPaginationMeta {
  /// Returns a new [CursorPaginationMeta] instance.
  CursorPaginationMeta({

    required  this.hasMore,

     this.nextCursor,
  });

  @JsonKey(
    
    name: r'has_more',
    required: true,
    includeIfNull: false,
  )


  final bool hasMore;



      /// Opaque base64-encoded cursor. Pass as `cursor=` on the next request. Null when has_more=false. Never parse or construct manually. 
  @JsonKey(
    
    name: r'next_cursor',
    required: false,
    includeIfNull: false,
  )


  final String? nextCursor;





    @override
    bool operator ==(Object other) => identical(this, other) || other is CursorPaginationMeta &&
      other.hasMore == hasMore &&
      other.nextCursor == nextCursor;

    @override
    int get hashCode =>
        hasMore.hashCode +
        nextCursor.hashCode;

  factory CursorPaginationMeta.fromJson(Map<String, dynamic> json) => _$CursorPaginationMetaFromJson(json);

  Map<String, dynamic> toJson() => _$CursorPaginationMetaToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }

}

