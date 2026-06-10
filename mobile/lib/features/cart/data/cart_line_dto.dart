class CartLineDto {
  const CartLineDto({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.sellerId,
    required this.title,
    required this.priceMinor,
    required this.qty,
    this.sellerName = '',
    this.variantLabel = '',
    this.coverImageUrl,
    this.reservedUntil,
  });

  factory CartLineDto.fromJson(Map<String, dynamic> json) => CartLineDto(
        id: json['id'] as String,
        productId: (json['product_id'] as num).toInt(),
        variantId: (json['variant_id'] as num).toInt(),
        sellerId: (json['seller_id'] as num).toInt(),
        title: json['title'] as String,
        priceMinor: (json['price_minor'] as num).toInt(),
        qty: (json['qty'] as num).toInt(),
        sellerName: (json['seller_name'] as String?) ?? '',
        variantLabel: (json['variant_label'] as String?) ?? '',
        coverImageUrl: json['cover_image_url'] as String?,
        reservedUntil: json['reserved_until'] != null
            ? DateTime.tryParse(json['reserved_until'] as String)
            : null,
      );

  final String id;
  final int productId;
  final int variantId;
  final int sellerId;
  final String title;
  final int priceMinor;
  final int qty;

  /// CT-01: the seller's display name (group header). Empty → fall back to `#id`.
  final String sellerName;

  /// CT-05: the variant's colour/size label, e.g. "Siyah, M". Empty when none.
  final String variantLabel;
  final String? coverImageUrl;
  final DateTime? reservedUntil;

  int get lineTotalMinor => priceMinor * qty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'variant_id': variantId,
        'seller_id': sellerId,
        'title': title,
        'price_minor': priceMinor,
        'qty': qty,
        'seller_name': sellerName,
        'variant_label': variantLabel,
        if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
        if (reservedUntil != null)
          'reserved_until': reservedUntil!.toIso8601String(),
      };

  CartLineDto copyWith({int? qty}) => CartLineDto(
        id: id,
        productId: productId,
        variantId: variantId,
        sellerId: sellerId,
        title: title,
        priceMinor: priceMinor,
        qty: qty ?? this.qty,
        sellerName: sellerName,
        variantLabel: variantLabel,
        coverImageUrl: coverImageUrl,
        reservedUntil: reservedUntil,
      );
}
