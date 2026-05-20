import 'package:flutter_test/flutter_test.dart';

import 'package:mopro/main.dart';

void main() {
  testWidgets('placeholder smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MoproApp());
    expect(find.text('Mopro'), findsOneWidget);
  });
}
