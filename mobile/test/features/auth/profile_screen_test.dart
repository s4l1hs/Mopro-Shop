import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/auth/auth_profile_notifier.dart';
import 'package:mopro/features/auth/profile_screen.dart';

class _StubProfileNotifier extends AuthProfileNotifier {
  _StubProfileNotifier(this._state);
  final ProfileState _state;

  @override
  ProfileState build() => _state;

  @override
  void onNameFirstChanged(String v) {}

  @override
  void onNameLastChanged(String v) {}

  @override
  void onLocaleChanged(String? v) {}

  @override
  Future<void> submit() async {}
}

Widget _buildApp(ProfileState state) => ProviderScope(
      overrides: [
        authProfileNotifierProvider.overrideWith(
          () => _StubProfileNotifier(state),
        ),
      ],
      child: const MaterialApp(home: ProfileCompletionScreen()),
    );

void main() {
  testWidgets('renders without exception', (tester) async {
    await tester.pumpWidget(_buildApp(const ProfileState()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'submit button disabled when name fields are empty',
    (tester) async {
      await tester.pumpWidget(_buildApp(const ProfileState()));
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'submit button enabled when both name fields are filled',
    (tester) async {
      await tester.pumpWidget(
        _buildApp(const ProfileState(nameFirst: 'Ali', nameLast: 'Veli')),
      );
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    },
  );
}
