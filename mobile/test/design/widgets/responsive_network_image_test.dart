import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/widgets/responsive_network_image.dart';

void main() {
  testWidgets('sets ?w= from logical width × DPR on the underlying image',
      (tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: ResponsiveNetworkImage(imageUrl: 'http://cdn.test/i.jpg'),
          ),
        ),
      ),
    );

    // 300 logical × 2.0 DPR = 600 physical → w=600.
    final cni = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(Uri.parse(cni.imageUrl).queryParameters['w'], '600');
  });
}
