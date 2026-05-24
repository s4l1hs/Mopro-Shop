// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pagination_meta.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaginationMeta _$PaginationMetaFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PaginationMeta',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const ['page', 'per_page', 'total', 'total_pages'],
        );
        final val = PaginationMeta(
          page: $checkedConvert('page', (v) => (v as num).toInt()),
          perPage: $checkedConvert('per_page', (v) => (v as num).toInt()),
          total: $checkedConvert('total', (v) => (v as num).toInt()),
          totalPages: $checkedConvert('total_pages', (v) => (v as num).toInt()),
        );
        return val;
      },
      fieldKeyMap: const {'perPage': 'per_page', 'totalPages': 'total_pages'},
    );

Map<String, dynamic> _$PaginationMetaToJson(PaginationMeta instance) =>
    <String, dynamic>{
      'page': instance.page,
      'per_page': instance.perPage,
      'total': instance.total,
      'total_pages': instance.totalPages,
    };
