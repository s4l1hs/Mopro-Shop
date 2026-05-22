import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/auth/auth_otp_notifier.dart';
import 'package:mopro/features/auth/otp_screen.dart';

const _phone = '+905001234567';

class _StubOtpNotifier extends AuthOtpNotifier {
  _StubOtpNotifier(this._state);
  final OtpState _state;

  @override
  OtpState build(String phone) => _state;

  @override
  void onCodeChanged(String c) {}

  @override
  Future<void> submit() async {}

  @override
  Future<void> resend() async {}
}

Widget _buildApp(OtpState state) => ProviderScope(
      overrides: [
        authOtpNotifierProvider.overrideWith(() => _StubOtpNotifier(state)),
      ],
      child: const MaterialApp(home: OtpScreen(phone: _phone)),
    );

void main() {
  testWidgets('renders without exception', (tester) async {
    await tester.pumpWidget(_buildApp(const OtpState(phone: _phone)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders 6 OTP input boxes', (tester) async {
    await tester.pumpWidget(_buildApp(const OtpState(phone: _phone)));
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(6));
  });

  testWidgets('submit button disabled when code is empty', (tester) async {
    await tester.pumpWidget(_buildApp(const OtpState(phone: _phone)));
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('shows CircularProgressIndicator when loading', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        const OtpState(phone: _phone, code: '123456', isLoading: true),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'shows resend TextButton when countdown reaches zero',
    (tester) async {
      await tester.pumpWidget(_buildApp(const OtpState(phone: _phone)));
      await tester.pump();
      expect(find.byType(TextButton), findsOneWidget);
    },
  );
}
