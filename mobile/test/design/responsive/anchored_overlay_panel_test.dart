import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/responsive/anchored_overlay_panel.dart';

import '../../_support/test_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(800, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Widget _panel({
  required String label,
  Object? exclusivityGroup,
  bool openOnTap = true,
  bool openOnHover = true,
  bool openOnFocus = true,
  bool closeOnOutsideTap = true,
  Duration openDelay = Duration.zero,
  Duration closeDelay = Duration.zero,
}) {
  return AnchoredOverlayPanel(
    openOnTap: openOnTap,
    openOnHover: openOnHover,
    openOnFocus: openOnFocus,
    closeOnOutsideTap: closeOnOutsideTap,
    openDelay: openDelay,
    closeDelay: closeDelay,
    exclusivityGroup: exclusivityGroup,
    trigger: Container(
      key: Key('trigger_$label'),
      width: 80,
      height: 32,
      color: Colors.orange,
      alignment: Alignment.center,
      child: Text('T_$label'),
    ),
    panelBuilder: (_, __) => Material(
      child: Container(
        key: Key('panel_$label'),
        width: 200,
        height: 100,
        color: Colors.white,
        alignment: Alignment.center,
        child: Text('P_$label'),
      ),
    ),
  );
}

void main() {
  setUpAll(initTestEnv);
  setUp(debugResetAnchoredOverlayPanelRegistry);

  group('AnchoredOverlayPanel — open / close triggers', () {
    testWidgets('tap on trigger toggles open/close', (tester) async {
      await _pump(tester, child: _panel(label: 'a'));
      expect(find.byKey(const Key('panel_a')), findsNothing);
      await tester.tap(find.byKey(const Key('trigger_a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsOneWidget);
      await tester.tap(find.byKey(const Key('trigger_a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsNothing);
    });

    testWidgets('Escape closes when open', (tester) async {
      await _pump(tester, child: _panel(label: 'a'));
      await tester.tap(find.byKey(const Key('trigger_a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsNothing);
    });

    testWidgets('outside tap closes', (tester) async {
      await _pump(
        tester,
        child: Stack(
          children: [
            Positioned(top: 100, left: 100, child: _panel(label: 'a')),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('trigger_a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsOneWidget);
      // Tap on an empty region of the dismisser overlay.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsNothing);
    });

    testWidgets('openDelay debounces hover open', (tester) async {
      await _pump(
        tester,
        child: _panel(
          label: 'a',
          openOnTap: false,
          openDelay: const Duration(milliseconds: 100),
        ),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('trigger_a'))),
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Still under the 100ms threshold — panel not yet shown.
      expect(find.byKey(const Key('panel_a')), findsNothing);
      await tester.pump(const Duration(milliseconds: 80));
      // Past the threshold — panel opens.
      expect(find.byKey(const Key('panel_a')), findsOneWidget);
    });
  });

  group('AnchoredOverlayPanel — exclusivity', () {
    testWidgets('opening B closes A when both in the same group',
        (tester) async {
      // openOnFocus and closeOnOutsideTap disabled so the test isolates the
      // exclusivity path — otherwise the focus-leave on tap B or the
      // outside-tap dismisser would also close panel A and the test
      // wouldn't distinguish what triggered the close.
      await _pump(
        tester,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _panel(
              label: 'a',
              exclusivityGroup: 'menu',
              closeOnOutsideTap: false,
              openOnFocus: false,
            ),
            const SizedBox(width: 8),
            _panel(
              label: 'b',
              exclusivityGroup: 'menu',
              closeOnOutsideTap: false,
              openOnFocus: false,
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('trigger_a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsOneWidget);
      expect(find.byKey(const Key('panel_b')), findsNothing);

      await tester.tap(find.byKey(const Key('trigger_b')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsNothing);
      expect(find.byKey(const Key('panel_b')), findsOneWidget);
    });

    testWidgets('different groups remain independent', (tester) async {
      await _pump(
        tester,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _panel(
              label: 'a',
              exclusivityGroup: 'g1',
              closeOnOutsideTap: false,
              openOnFocus: false,
            ),
            const SizedBox(width: 8),
            _panel(
              label: 'b',
              exclusivityGroup: 'g2',
              closeOnOutsideTap: false,
              openOnFocus: false,
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const Key('trigger_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trigger_b')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_a')), findsOneWidget);
      expect(find.byKey(const Key('panel_b')), findsOneWidget);
    });
  });
}
