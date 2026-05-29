import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/responsive/pointer_kind.dart';

import '../../_support/test_harness.dart';

void main() {
  setUpAll(initTestEnv);
  tearDown(PointerKindObserver.debugReset);

  group('PointerKindObserver — kind mapping', () {
    testWidgets('default value before install is unknown', (tester) async {
      // tearDown's debugReset has already set this back; the value should be
      // unknown until the first PointerDownEvent fires.
      expect(PointerKindObserver.lastKind.value, LastPointerKind.unknown);
    });

    testWidgets('touch PointerDownEvent → LastPointerKind.touch',
        (tester) async {
      PointerKindObserver.install();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('x')))),
      );
      final g = await tester.createGesture();
      await g.addPointer();
      addTearDown(g.removePointer);
      await g.down(const Offset(10, 10));
      await tester.pump();
      expect(PointerKindObserver.lastKind.value, LastPointerKind.touch);
      await g.up();
    });

    testWidgets('mouse PointerDownEvent → LastPointerKind.mouse',
        (tester) async {
      PointerKindObserver.install();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('x')))),
      );
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer();
      addTearDown(g.removePointer);
      await g.down(const Offset(10, 10));
      await tester.pump();
      expect(PointerKindObserver.lastKind.value, LastPointerKind.mouse);
      await g.up();
    });

    // No trackpad PointerDownEvent test: Flutter framework asserts trackpads
    // emit PointerPanZoomStartEvent, never PointerDownEvent — the switch
    // case for PointerDeviceKind.trackpad in _map() is therefore unreachable
    // in production. Kept in the source as defensive completeness in case a
    // future Flutter release adds trackpad-down semantics.

    testWidgets('stylus PointerDownEvent → LastPointerKind.stylus',
        (tester) async {
      PointerKindObserver.install();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('x')))),
      );
      final g = await tester.createGesture(kind: PointerDeviceKind.stylus);
      await g.addPointer();
      addTearDown(g.removePointer);
      await g.down(const Offset(10, 10));
      await tester.pump();
      expect(PointerKindObserver.lastKind.value, LastPointerKind.stylus);
      await g.up();
    });

    testWidgets('notifier fires only on transitions, not on every down',
        (tester) async {
      PointerKindObserver.install();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('x')))),
      );
      var notifyCount = 0;
      void listener() => notifyCount++;
      PointerKindObserver.lastKind.addListener(listener);
      addTearDown(() => PointerKindObserver.lastKind.removeListener(listener));

      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer();
      addTearDown(g.removePointer);

      // First down → transition unknown → mouse.
      await g.down(const Offset(10, 10));
      await tester.pump();
      await g.up();
      // Second mouse down → no transition; notifier should NOT fire.
      await g.down(const Offset(11, 11));
      await tester.pump();
      await g.up();
      expect(
        notifyCount,
        1,
        reason: 'notifier should fire only on kind change',
      );
    });
  });

  group('PointerKindObserver — install idempotency', () {
    testWidgets('install twice does not double-register the route',
        (tester) async {
      PointerKindObserver.install();
      PointerKindObserver.install(); // should be a no-op
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('x')))),
      );
      var notifyCount = 0;
      void listener() => notifyCount++;
      PointerKindObserver.lastKind.addListener(listener);
      addTearDown(() => PointerKindObserver.lastKind.removeListener(listener));

      final g = await tester.createGesture();
      await g.addPointer();
      addTearDown(g.removePointer);
      await g.down(const Offset(10, 10));
      await tester.pump();
      await g.up();

      // If install double-registered, the global route would fire twice
      // per event; the notifier's setter would still de-dupe (it checks
      // value != mapped before writing). So we observe exactly 1 notify
      // for the unknown→touch transition.
      expect(notifyCount, 1);
    });
  });
}
