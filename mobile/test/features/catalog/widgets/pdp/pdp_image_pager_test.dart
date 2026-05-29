import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_image_pager.dart';

import '../../../../_support/test_harness.dart';

const _urls = ['https://x.test/1.png', 'https://x.test/2.png'];

Future<void> _pump(
  WidgetTester tester, {
  required bool enableHoverZoom,
}) async {
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: PdpImagePager(
            imageUrls: _urls,
            enableHoverZoom: enableHoverZoom,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('mouse hover shows the zoom lens when enableHoverZoom is true',
      (tester) async {
    await _pump(tester, enableHoverZoom: true);
    expect(find.byKey(PdpImagePager.zoomOverlayKey), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PdpImagePager)));
    await tester.pump();

    expect(find.byKey(PdpImagePager.zoomOverlayKey), findsOneWidget);
  });

  testWidgets('no zoom lens when enableHoverZoom is false', (tester) async {
    await _pump(tester, enableHoverZoom: false);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PdpImagePager)));
    await tester.pump();

    expect(find.byKey(PdpImagePager.zoomOverlayKey), findsNothing);
  });

  testWidgets('thumbnail tap switches the main image index', (tester) async {
    var lastIndex = -1;
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: PdpImagePager(
              imageUrls: _urls,
              onIndexChanged: (i) => lastIndex = i,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Tap the second thumbnail (the GestureDetectors in the thumb strip).
    await tester.tap(find.byType(GestureDetector).last);
    await tester.pump();
    expect(lastIndex, 1);
  });
}
