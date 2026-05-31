import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/catalog/pdp/qa/pdp_qa_tab.dart';

/// `/products/:id/questions` — the standalone, full questions list for a
/// product. Reuses [PdpQaTab] (same list, sort, ask CTA, and pagination) under
/// its own app bar; tapping a question opens the detail thread.
class ProductQuestionsScreen extends StatelessWidget {
  const ProductQuestionsScreen({required this.productId, super.key});

  final int productId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('product.qa_tab'.tr())),
      body: PdpQaTab(productId: productId),
    );
  }
}
