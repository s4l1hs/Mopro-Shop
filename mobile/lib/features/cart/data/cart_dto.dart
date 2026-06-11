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
    this.basketDiscountMinor = 0,
    this.couponCode = '',
    this.couponDiscountMinor = 0,
    this.couponMessage = '',
  });

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
        basketDiscountMinor:
            (json['basket_discount_minor'] as num?)?.toInt() ?? 0,
        couponCode: (json['coupon_code'] ?? '') as String,
        couponDiscountMinor:
            (json['coupon_discount_minor'] as num?)?.toInt() ?? 0,
        couponMessage: (json['coupon_message'] ?? '') as String,
      );

  factory CartDto.empty() => const CartDto(
        id: '',
        userId: 0,
        lines: [],
        totalsBySeller: [],
        grandTotalMinor: 0,
        kdvIncludedMinor: 0,
      );

  final String id;
  final int userId;
  final List<CartLineDto> lines;
  final List<SellerTotalDto> totalsBySeller;
  final int grandTotalMinor;
  final int kdvIncludedMinor;

  /// CT-09: the seller-funded "Sepette indirim" total (Σ list − charged). 0 when
  /// no line carries a basket discount. grandTotalMinor is already discounted, so
  /// the pre-discount subtotal = grandTotalMinor + basketDiscountMinor + couponDiscountMinor.
  final int basketDiscountMinor;

  /// CT-03 coupon: the applied code ('' when none/invalid), its discount slice
  /// (folded into grandTotalMinor), and a reason string when an entered code was
  /// NOT applied (e.g. 'expired', 'min_basket') so the UI can explain why.
  final String couponCode;
  final int couponDiscountMinor;
  final String couponMessage;

  bool get isEmpty => lines.isEmpty;
  bool get isAboveTotalLimit => grandTotalMinor >= 5000000; // ₺50,000 in minor units
  bool get isAtItemLimit => lines.length >= 50;

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'lines': lines.map((l) => l.toJson()).toList(),
        'totals_by_seller':
            totalsBySeller.map((t) => t.toJson()).toList(),
        'grand_total_minor': grandTotalMinor,
        'kdv_included_minor': kdvIncludedMinor,
        'basket_discount_minor': basketDiscountMinor,
        'coupon_code': couponCode,
        'coupon_discount_minor': couponDiscountMinor,
        'coupon_message': couponMessage,
      };
}
