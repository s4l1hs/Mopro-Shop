// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cursor_pagination_meta.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CursorPaginationMeta _$CursorPaginationMetaFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'CursorPaginationMeta',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['has_more']);
    final val = CursorPaginationMeta(
      hasMore: $checkedConvert('has_more', (v) => v as bool),
      nextCursor: $checkedConvert('next_cursor', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {'hasMore': 'has_more', 'nextCursor': 'next_cursor'},
);

Map<String, dynamic> _$CursorPaginationMetaToJson(
  CursorPaginationMeta instance,
) => <String, dynamic>{
  'has_more': instance.hasMore,
  if (instance.nextCursor != null) 'next_cursor': instance.nextCursor,
};
