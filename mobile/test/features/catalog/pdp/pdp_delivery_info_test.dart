import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_delivery_info.dart';
import 'package:mopro_api/mopro_api.dart';

// In widget tests the easy_localization bundle is not loaded, so `.tr()` returns
// the translation KEY (see reference_flutter_test_i18n). We assert on the keyed
// output to verify which copy path the widget chose, not the resolved string.

Future<void> _pump(WidgetTester tester, DeliveryEta eta) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: PdpDeliveryInfo(eta: eta)),
    ),
  );
}

void main() {
  testWidgets('confident estimate uses the firm copy + shipping icon',
      (tester) async {
    await _pump(
      tester,
      DeliveryEta(minDays: 2, maxDays: 3, confident: true, dispatchCity: 'istanbul'),
    );

    expect(find.text('product.delivery_eta_confident'), findsOneWidget);
    expect(find.text('product.delivery_eta_estimate'), findsNothing);
    expect(find.text('product.delivery_eta_from'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
  });

  testWidgets('fallback estimate uses the hedged copy', (tester) async {
    await _pump(
      tester,
      DeliveryEta(minDays: 2, maxDays: 5, confident: false),
    );

    expect(find.text('product.delivery_eta_estimate'), findsOneWidget);
    expect(find.text('product.delivery_eta_confident'), findsNothing);
  });

  testWidgets('omits the origin line when dispatchCity is absent',
      (tester) async {
    await _pump(
      tester,
      DeliveryEta(minDays: 2, maxDays: 3, confident: true),
    );

    expect(find.text('product.delivery_eta_from'), findsNothing);
  });
}
