import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/auth/auth_phone_notifier.dart';
import 'package:mopro/features/auth/login_screen.dart';

class _StubPhoneNotifier extends AuthPhoneNotifier {
  _StubPhoneNotifier(this._state);
  final PhoneState _state;

  @override
  PhoneState build() => _state;

  @override
  void onPhoneChanged(String digits) {}

  @override
  Future<void> submit() async {}
}

Widget _buildApp(PhoneState state) => ProviderScope(
      overrides: [
        authPhoneNotifierProvider.overrideWith(() => _StubPhoneNotifier(state)),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );

void main() {
  testWidgets('renders without exception', (tester) async {
    await tester.pumpWidget(_buildApp(const PhoneState()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'submit button disabled when fewer than 10 digits',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(const PhoneState(rawDigits: '500123')),
      );
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    },
  );

  testWidgets('submit button enabled when 10 digits entered', (tester) async {
    await tester.pumpWidget(
      _buildApp(const PhoneState(rawDigits: '5001234567')),
    );
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('shows CircularProgressIndicator when loading', (tester) async {
    await tester.pumpWidget(
      _buildApp(const PhoneState(rawDigits: '5001234567', isLoading: true)),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('submit button disabled while loading', (tester) async {
    await tester.pumpWidget(
      _buildApp(const PhoneState(rawDigits: '5001234567', isLoading: true)),
    );
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
