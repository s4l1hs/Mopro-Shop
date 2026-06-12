import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/widgets/pdp_image_gallery.dart';

// PD-06: the mobile gallery renders a tappable thumbnail strip when it carries
// more than one image (replacing the former dot indicator), and no strip for a
// single image.

Widget _wrap(List<String> urls) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 375,
          height: 375,
          child: PdpImageGallery(imageUrls: urls, heroTag: 'g'),
        ),
      ),
    );

void main() {
  testWidgets('multi-image gallery renders one thumb per image', (tester) async {
    final urls = [for (var i = 1; i <= 4; i++) 'https://x.test/$i.png'];
    await tester.pumpWidget(_wrap(urls));
    await tester.pump();

    // 4 page images + 4 thumbs = 8 network images... but the PageView only
    // builds the visible page, so assert on the thumb containers instead:
    // 4 bordered 48x48 GestureDetector thumbs.
    final thumbs = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxWidth == 48,
    );
    expect(thumbs, findsNWidgets(4));
  });

  testWidgets('tapping a thumb pages the gallery', (tester) async {
    final urls = [for (var i = 1; i <= 3; i++) 'https://x.test/$i.png'];
    await tester.pumpWidget(_wrap(urls));
    await tester.pump();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.page, 0);

    final thumbs = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxWidth == 48,
    );
    await tester.tap(thumbs.at(2));
    await tester.pumpAndSettle();

    expect(
      pageView.controller!.page,
      2,
      reason: 'tapping the 3rd thumb must page to index 2',
    );
  });

  testWidgets('single image renders no thumbnail strip', (tester) async {
    await tester.pumpWidget(_wrap(['https://x.test/only.png']));
    await tester.pump();

    final thumbs = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxWidth == 48,
    );
    expect(thumbs, findsNothing);
  });
}
