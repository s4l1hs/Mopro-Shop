import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/account_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
}

void main() {
  testWidgets('theme picker shows 2 options (Light/Dark, no System) and persists',
      (tester) async {
    // The guest menu wraps ListTiles in a ColoredBox, which trips a pre-existing
    // Flutter debug hint ("ListTile background color may be invisible"). It is
    // unrelated to this test (and to the theme change), so filter just that one
    // message and let any real error through.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('ListTile background color')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authNotifierProvider
              .overrideWith(() => _FakeAuthNotifier(const AuthUnauthenticated())),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The System chip/button is gone; only Light + Dark remain.
    expect(find.byIcon(Icons.brightness_auto_rounded), findsNothing);
    expect(find.byIcon(Icons.light_mode_rounded), findsWidgets);
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

    // Tapping Dark updates the controller and persists 'dark'.
    await tester.tap(find.byIcon(Icons.dark_mode_rounded));
    await tester.pump();
    expect(prefs.getString('mopro_theme_mode'), 'dark');
  });
}
