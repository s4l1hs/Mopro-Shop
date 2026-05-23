class SellerTotalDto {
  const SellerTotalDto({
    required this.sellerId,
    required this.itemsMinor,
    required this.shippingMinor,
    required this.totalMinor,
  });

  final int sellerId;
  final int itemsMinor;
  final int shippingMinor;
  final int totalMinor;

  factory SellerTotalDto.fromJson(Map<String, dynamic> json) => SellerTotalDto(
        sellerId: (json['seller_id'] as num).toInt(),
        itemsMinor: (json['items_minor'] as num).toInt(),
        shippingMinor: (json['shipping_minor'] as num).toInt(),
        totalMinor: (json['total_minor'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'seller_id': sellerId,
        'items_minor': itemsMinor,
        'shipping_minor': shippingMinor,
        'total_minor': totalMinor,
      };
}
