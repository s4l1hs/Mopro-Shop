class OrderItemDto {
  const OrderItemDto({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.variantId,
    required this.title,
    required this.priceMinor,
    required this.qty,
    required this.commissionPctBps,
    this.coverImageUrl,
  });

  final int id;
  final int orderId;
  final int productId;
  final int variantId;
  final String title;
  final int priceMinor;
  final int qty;
  final int commissionPctBps;
  final String? coverImageUrl;

  int get lineTotalMinor => priceMinor * qty;

  factory OrderItemDto.fromJson(Map<String, dynamic> json) => OrderItemDto(
        id: (json['id'] as num).toInt(),
        orderId: (json['order_id'] as num?)?.toInt() ?? 0,
        productId: (json['product_id'] as num).toInt(),
        variantId: (json['variant_id'] as num).toInt(),
        title: json['title'] as String,
        priceMinor: (json['price_minor'] as num).toInt(),
        qty: (json['qty'] as num?)?.toInt() ??
            (json['quantity'] as num?)?.toInt() ??
            1,
        commissionPctBps: (json['commission_pct_bps'] as num?)?.toInt() ?? 0,
        coverImageUrl: json['cover_image_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'order_id': orderId,
        'product_id': productId,
        'variant_id': variantId,
        'title': title,
        'price_minor': priceMinor,
        'qty': qty,
        'commission_pct_bps': commissionPctBps,
        if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      };
}
