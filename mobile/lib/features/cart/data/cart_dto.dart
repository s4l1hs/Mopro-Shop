import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';

class CartDto {
  const CartDto({
    required this.id,
    required this.userId,
    required this.lines,
    required this.totalsBySeller,
    required this.grandTotalMinor,
    required this.kdvIncludedMinor,
  });

  final String id;
  final int userId;
  final List<CartLineDto> lines;
  final List<SellerTotalDto> totalsBySeller;
  final int grandTotalMinor;
  final int kdvIncludedMinor;

  bool get isEmpty => lines.isEmpty;
  bool get isAboveTotalLimit => grandTotalMinor >= 5000000; // ₺50,000 in minor units
  bool get isAtItemLimit => lines.length >= 50;

  factory CartDto.fromJson(Map<String, dynamic> json) => CartDto(
        id: (json['id'] ?? '') as String,
        userId: (json['user_id'] as num).toInt(),
        lines: (json['lines'] as List<dynamic>? ?? [])
            .map((e) => CartLineDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalsBySeller:
            (json['totals_by_seller'] as List<dynamic>? ?? [])
                .map(
                  (e) =>
                      SellerTotalDto.fromJson(e as Map<String, dynamic>),
                )
                .toList(),
        grandTotalMinor: (json['grand_total_minor'] as num?)?.toInt() ?? 0,
        kdvIncludedMinor:
            (json['kdv_included_minor'] as num?)?.toInt() ?? 0,
      );

  factory CartDto.empty() => const CartDto(
        id: '',
        userId: 0,
        lines: [],
        totalsBySeller: [],
        grandTotalMinor: 0,
        kdvIncludedMinor: 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'lines': lines.map((l) => l.toJson()).toList(),
        'totals_by_seller':
            totalsBySeller.map((t) => t.toJson()).toList(),
        'grand_total_minor': grandTotalMinor,
        'kdv_included_minor': kdvIncludedMinor,
      };
}
