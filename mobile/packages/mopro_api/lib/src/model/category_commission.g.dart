// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_commission.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CategoryCommission _$CategoryCommissionFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'CategoryCommission',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'category_id',
            'market',
            'commission_pct_bps',
            'kdv_pct_bps',
          ],
        );
        final val = CategoryCommission(
          categoryId: $checkedConvert('category_id', (v) => (v as num).toInt()),
          market: $checkedConvert('market', (v) => v as String),
          commissionPctBps: $checkedConvert(
            'commission_pct_bps',
            (v) => (v as num).toInt(),
          ),
          kdvPctBps: $checkedConvert('kdv_pct_bps', (v) => (v as num).toInt()),
        );
        return val;
      },
      fieldKeyMap: const {
        'categoryId': 'category_id',
        'commissionPctBps': 'commission_pct_bps',
        'kdvPctBps': 'kdv_pct_bps',
      },
    );

Map<String, dynamic> _$CategoryCommissionToJson(CategoryCommission instance) =>
    <String, dynamic>{
      'category_id': instance.categoryId,
      'market': instance.market,
      'commission_pct_bps': instance.commissionPctBps,
      'kdv_pct_bps': instance.kdvPctBps,
    };
