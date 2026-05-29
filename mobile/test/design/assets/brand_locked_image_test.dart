import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/assets/brand_locked_image.dart';
import 'package:mopro/design/theme.dart';

const _asset = 'assets/images/Mopro shop yazılı siyah.png';

void main() {
  testWidgets('paints the documented background regardless of theme',
      (tester) async {
    const bg = Color(0xFFEEEEEE);

    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: BrandLockedImage(
              _asset,
              background: bg,
              width: 40,
              height: 40,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(of: find.byType(Image), matching: find.byType(Container))
            .first,
      );
      expect(
        container.color,
        bg,
        reason: 'background must match in ${theme.brightness}',
      );
    }
  });
}
