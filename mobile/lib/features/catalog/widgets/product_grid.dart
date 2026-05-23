import 'package:flutter/material.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro_api/mopro_api.dart';

class ProductGrid extends StatelessWidget {
  const ProductGrid({
    required this.products,
    required this.onProductTap,
    super.key,
  });

  final List<ProductSummary> products;
  final void Function(ProductSummary) onProductTap;

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
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
