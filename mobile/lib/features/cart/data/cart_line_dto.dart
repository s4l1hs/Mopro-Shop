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
    this.listPriceMinor = 0,
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
        listPriceMinor: (json['list_price_minor'] as num?)?.toInt() ?? 0,
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

  /// CT-09: the pre-basket-discount unit price (strikethrough). 0 when the line
  /// carries no basket discount (priceMinor is already the charged unit).
  final int listPriceMinor;
  final String? coverImageUrl;
  final DateTime? reservedUntil;

  /// True when a seller-funded basket discount applies to this line (CT-09).
  bool get hasBasketDiscount => listPriceMinor > priceMinor;

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
        if (listPriceMinor > 0) 'list_price_minor': listPriceMinor,
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
        listPriceMinor: listPriceMinor,
        coverImageUrl: coverImageUrl,
        reservedUntil: reservedUntil,
      );
}
