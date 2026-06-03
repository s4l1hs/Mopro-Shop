import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/a11y_contrast.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/tokens.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('wcagContrast sanity', () {
    test('black on white is 21:1', () {
      expect(
        wcagContrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
    });
    test('identical colors are 1:1', () {
      expect(
        wcagContrast(const Color(0xFF777777), const Color(0xFF777777)),
        closeTo(1, 1e-9),
      );
    });
    test('is symmetric', () {
      const a = Color(0xFFCA4E00);
      const b = Color(0xFFFFFFFF);
      expect(wcagContrast(a, b), closeTo(wcagContrast(b, a), 1e-9));
    });
  });

  test('documented brand contrast pairs meet WCAG thresholds', () {
    final light = buildLightTheme().colorScheme;
    final dark = buildDarkTheme().colorScheme;

    final pairs = <({String name, Color fg, Color bg, double min, bool backlog})>[
      (
        name: '#CA4E00 on #FFFFFF (text)',
        fg: MoproTokens.primaryLight,
        bg: MoproTokens.surfaceLight,
        min: 4.5,
        backlog: false,
      ),
      (
        // P-020 (PARITY_AUDIT): primaryDark nudged #E36925 → #E97230 so brand
        // orange clears AA (4.5:1) as text on surfaceDark — was 4.26:1 Backlog.
        name: '#E97230 on surfaceDark (text)',
        fg: MoproTokens.primaryDark,
        bg: MoproTokens.surfaceDark,
        min: 4.5,
        backlog: false,
      ),
      (
        name: '#FFFFFF on #CA4E00 (CTA text)',
        fg: MoproTokens.onPrimaryLight,
        bg: MoproTokens.primaryLight,
        min: 4.5,
        backlog: false,
      ),
      (
        name: 'onSurfaceVariant on surface (light)',
        fg: light.onSurfaceVariant,
        bg: light.surface,
        min: 4.5,
        backlog: false,
      ),
      (
        name: 'onSurfaceVariant on surface (dark)',
        fg: dark.onSurfaceVariant,
        bg: dark.surface,
        min: 4.5,
        backlog: false,
      ),
      (
        name: '#CA4E00 focus ring on surface (light)',
        fg: MoproTokens.primaryLight,
        bg: light.surface,
        min: 3.0,
        backlog: false,
      ),
      (
        name: '#CA4E00 rail bar on surfaceContainer (light)',
        fg: MoproTokens.primaryLight,
        bg: light.surfaceContainer,
        min: 3.0,
        backlog: false,
      ),
    ];

    final table = StringBuffer('\n| Pair | Ratio | Threshold | Status |\n')
      ..write('| --- | --- | --- | --- |\n');
    final failures = <String>[];
    for (final p in pairs) {
      final ratio = wcagContrast(p.fg, p.bg);
      final pass = ratio >= p.min;
      final status = pass
          ? 'Pass'
          : p.backlog
              ? 'FAIL (Backlog)'
              : 'FAIL';
      table.write(
        '| ${p.name} | ${ratio.toStringAsFixed(2)}:1 | '
        '${p.min.toStringAsFixed(1)}:1 | $status |\n',
      );
      if (!pass && !p.backlog) {
        failures.add('${p.name} = ${ratio.toStringAsFixed(2)}:1');
      }
    }
    // ignore: avoid_print
    print(table);
    expect(
      failures,
      isEmpty,
      reason: 'Contrast pairs below threshold (surface as Backlog, do not '
          'silently change brand colors): $failures',
    );
  });
}
