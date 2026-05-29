import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/assets/themed_image_icon.dart';

// Real declared asset so AssetImage resolves cleanly in the test bundle; the
// assertions check the resolved tint on the ImageIcon, not decoded pixels.
const _asset = 'assets/images/Yazısız logo siyah.png';

void main() {
  testWidgets('tints with the ambient IconTheme color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(color: Color(0xFF112233)),
          child: ThemedImageIcon(_asset, size: 20),
        ),
      ),
    );
    final icon = tester.widget<ImageIcon>(find.byType(ImageIcon));
    expect(icon.color, const Color(0xFF112233));
    expect(icon.size, 20);
  });

  testWidgets('follows the surrounding icon color, flipping light vs dark',
      (tester) async {
    Future<Color?> resolve(Color ambient) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IconTheme(
            data: IconThemeData(color: ambient),
            child: const ThemedImageIcon(_asset),
          ),
        ),
      );
      return tester.widget<ImageIcon>(find.byType(ImageIcon)).color;
    }

    // Light surface → dark icon; dark surface → light icon. The icon takes
    // whatever the ambient IconTheme dictates, so it flips with the theme.
    expect(await resolve(const Color(0xFF1A1A1A)), const Color(0xFF1A1A1A));
    expect(await resolve(const Color(0xFFF5F5F5)), const Color(0xFFF5F5F5));
  });

  testWidgets('honors an explicit color override over the IconTheme',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(color: Color(0xFF000000)),
          child: ThemedImageIcon(_asset, color: Color(0xFFCA4E00)),
        ),
      ),
    );
    expect(
      tester.widget<ImageIcon>(find.byType(ImageIcon)).color,
      const Color(0xFFCA4E00),
    );
  });
}
