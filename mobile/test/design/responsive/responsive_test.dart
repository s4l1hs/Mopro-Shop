import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/responsive/responsive.dart';

void main() {
  group('BreakpointResolver boundaries', () {
    test('width 0 → mobile', () {
      expect(BreakpointResolver.resolve(0), Breakpoint.mobile);
    });
    test('width 599 → mobile (just under tablet cutoff)', () {
      expect(BreakpointResolver.resolve(599), Breakpoint.mobile);
    });
    test('width 600 → tablet (boundary is inclusive of tablet)', () {
      expect(BreakpointResolver.resolve(600), Breakpoint.tablet);
    });
    test('width 1023 → tablet (just under desktop cutoff)', () {
      expect(BreakpointResolver.resolve(1023), Breakpoint.tablet);
    });
    test('width 1024 → desktop (boundary is inclusive of desktop)', () {
      expect(BreakpointResolver.resolve(1024), Breakpoint.desktop);
    });
    test('width 1025 → desktop', () {
      expect(BreakpointResolver.resolve(1025), Breakpoint.desktop);
    });
    test('very large widths still resolve to desktop', () {
      expect(BreakpointResolver.resolve(4096), Breakpoint.desktop);
    });
  });

  group('AdaptiveValue fallback chain', () {
    Widget wrap(Size size, ValueChanged<BuildContext> onBuild) {
      return MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(builder: (ctx) {
          onBuild(ctx);
          return const SizedBox.shrink();
        },),
      );
    }

    testWidgets('mobile-only value used at all breakpoints', (tester) async {
      const v = AdaptiveValue<int>(mobile: 1);
      late int m;
      late int t;
      late int d;
      await tester.pumpWidget(wrap(const Size(375, 800), (c) => m = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(768, 800), (c) => t = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(1440, 800), (c) => d = v.resolve(c)));
      expect(m, 1);
      expect(t, 1);
      expect(d, 1);
    });

    testWidgets('tablet overrides mobile; desktop falls through to tablet',
        (tester) async {
      const v = AdaptiveValue<int>(mobile: 1, tablet: 2);
      late int m;
      late int t;
      late int d;
      await tester.pumpWidget(wrap(const Size(375, 800), (c) => m = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(768, 800), (c) => t = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(1440, 800), (c) => d = v.resolve(c)));
      expect(m, 1);
      expect(t, 2);
      expect(d, 2, reason: 'desktop should fall back to tablet when null');
    });

    testWidgets('desktop overrides; tablet null falls back to mobile',
        (tester) async {
      const v = AdaptiveValue<int>(mobile: 1, desktop: 3);
      late int m;
      late int t;
      late int d;
      await tester.pumpWidget(wrap(const Size(375, 800), (c) => m = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(768, 800), (c) => t = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(1440, 800), (c) => d = v.resolve(c)));
      expect(m, 1);
      expect(t, 1, reason: 'tablet should fall back to mobile when null');
      expect(d, 3);
    });

    testWidgets('all three set — each breakpoint picks its own', (tester) async {
      const v = AdaptiveValue<int>(mobile: 1, tablet: 2, desktop: 3);
      late int m;
      late int t;
      late int d;
      await tester.pumpWidget(wrap(const Size(375, 800), (c) => m = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(768, 800), (c) => t = v.resolve(c)));
      await tester.pumpWidget(wrap(const Size(1440, 800), (c) => d = v.resolve(c)));
      expect((m, t, d), (1, 2, 3));
    });
  });

  group('ResponsiveBuilder branch selection', () {
    Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: child)),
      ),);
    }

    testWidgets('mobile size selects mobile branch', (tester) async {
      await pumpAt(
        tester,
        const Size(375, 800),
        ResponsiveBuilder(
          mobile: (_) => const Text('M', key: Key('m')),
          tablet: (_) => const Text('T', key: Key('t')),
          desktop: (_) => const Text('D', key: Key('d')),
        ),
      );
      expect(find.byKey(const Key('m')), findsOneWidget);
      expect(find.byKey(const Key('t')), findsNothing);
      expect(find.byKey(const Key('d')), findsNothing);
    });

    testWidgets('tablet size selects tablet branch', (tester) async {
      await pumpAt(
        tester,
        const Size(768, 800),
        ResponsiveBuilder(
          mobile: (_) => const Text('M', key: Key('m')),
          tablet: (_) => const Text('T', key: Key('t')),
          desktop: (_) => const Text('D', key: Key('d')),
        ),
      );
      expect(find.byKey(const Key('t')), findsOneWidget);
    });

    testWidgets('desktop size selects desktop branch', (tester) async {
      await pumpAt(
        tester,
        const Size(1440, 800),
        ResponsiveBuilder(
          mobile: (_) => const Text('M', key: Key('m')),
          tablet: (_) => const Text('T', key: Key('t')),
          desktop: (_) => const Text('D', key: Key('d')),
        ),
      );
      expect(find.byKey(const Key('d')), findsOneWidget);
    });

    testWidgets('desktop falls back to tablet when null', (tester) async {
      await pumpAt(
        tester,
        const Size(1440, 800),
        ResponsiveBuilder(
          mobile: (_) => const Text('M', key: Key('m')),
          tablet: (_) => const Text('T', key: Key('t')),
        ),
      );
      expect(find.byKey(const Key('t')), findsOneWidget);
    });

    testWidgets('tablet/desktop fall back to mobile when both null',
        (tester) async {
      await pumpAt(
        tester,
        const Size(1440, 800),
        ResponsiveBuilder(
          mobile: (_) => const Text('M', key: Key('m')),
        ),
      );
      expect(find.byKey(const Key('m')), findsOneWidget);
    });

    testWidgets(
        'embedded ResponsiveBuilder resolves against parent constraints, '
        'not window size', (tester) async {
      // Window is 1440 (desktop), but the inner SizedBox is mobile width.
      await pumpAt(
        tester,
        const Size(1440, 800),
        Center(
          child: SizedBox(
            width: 400,
            child: ResponsiveBuilder(
              mobile: (_) => const Text('inner-M', key: Key('im')),
              tablet: (_) => const Text('inner-T', key: Key('it')),
              desktop: (_) => const Text('inner-D', key: Key('id')),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('im')), findsOneWidget,
          reason: 'inner panel at 400px should resolve mobile',);
    });
  });

  group('CenteredContentColumn padding scales per breakpoint', () {
    Future<EdgeInsets> measurePadding(WidgetTester tester, Size size) async {
      late EdgeInsets captured;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          home: Scaffold(
            body: CenteredContentColumn(
              child: Builder(builder: (ctx) {
                // Walk up to find the Padding wrapper.
                captured = ctx
                        .findAncestorWidgetOfExactType<Padding>()!
                    .padding as EdgeInsets;
                return const SizedBox.shrink();
              },),
            ),
          ),
        ),
      ),);
      return captured;
    }

    testWidgets('mobile pad = 16', (tester) async {
      final p = await measurePadding(tester, const Size(375, 800));
      expect(p.left, Breakpoints.paddingMobile);
    });
    testWidgets('tablet pad = 24', (tester) async {
      final p = await measurePadding(tester, const Size(768, 800));
      expect(p.left, Breakpoints.paddingTablet);
    });
    testWidgets('desktop pad = 32', (tester) async {
      final p = await measurePadding(tester, const Size(1440, 800));
      expect(p.left, Breakpoints.paddingDesktop);
    });
  });

  group('HoverRegion smoke', () {
    testWidgets('builds child and exposes hovering=false initially',
        (tester) async {
      late bool seenHovering;
      await tester.pumpWidget(MaterialApp(
        home: HoverRegion(
          builder: (ctx, hovering) {
            seenHovering = hovering;
            return const SizedBox(width: 100, height: 100);
          },
        ),
      ),);
      expect(seenHovering, isFalse);
    });

    testWidgets('focus flips hovering=true', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var lastHover = false;
      await tester.pumpWidget(MaterialApp(
        home: HoverRegion(
          focusNode: node,
          builder: (ctx, hovering) {
            lastHover = hovering;
            return const SizedBox(width: 100, height: 100);
          },
        ),
      ),);
      node.requestFocus();
      await tester.pump();
      expect(lastHover, isTrue);
    });
  });
}
