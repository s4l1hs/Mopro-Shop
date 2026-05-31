import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/widgets/cancel_order_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('submit disabled until a reason is chosen', (tester) async {
    await tester.pumpWidget(
      _host(CancelOrderContent(onConfirm: (_, __) async {})),
    );
    await tester.pump();
    final submit = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submit.onPressed, isNull); // disabled

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('returns.cancel_reason_changed_mind').last);
    await tester.pumpAndSettle();
    final submit2 = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submit2.onPressed, isNotNull); // enabled
  });

  testWidgets('"other" reason surfaces the note field', (tester) async {
    await tester.pumpWidget(
      _host(CancelOrderContent(onConfirm: (_, __) async {})),
    );
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('returns.cancel_reason_other').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('error path keeps content open and shows error', (tester) async {
    await tester.pumpWidget(
      _host(
        CancelOrderContent(
          onConfirm: (_, __) async => throw Exception('boom'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('returns.cancel_reason_changed_mind').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(CancelOrderContent), findsOneWidget);
    expect(find.textContaining('cancel_error_generic'), findsOneWidget);
  });

  testWidgets('presenter: dialog on wide', (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    // Wide → Dialog
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () =>
                showCancelOrderDialog(ctx, onConfirm: (_, __) async {}),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });
}
