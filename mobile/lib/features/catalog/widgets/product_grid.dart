import 'package:flutter/material.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro_api/mopro_api.dart';

class ProductGrid extends StatelessWidget {
  const ProductGrid({
    required this.products,
    required this.onProductTap,
    this.crossAxisCount = 2,
    super.key,
  });

  final List<ProductSummary> products;
  final void Function(ProductSummary) onProductTap;

  /// Columns; 2 on mobile (default), 3/5 in the tablet/desktop two-column PLP.
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.68,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => ProductCard(
        product: products[i],
        onTap: () => onProductTap(products[i]),
      ),
    );
  }
}
