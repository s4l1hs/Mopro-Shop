import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/account/privacy/privacy_settings_screen.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/analytics/widgets/consent_banner.dart';

/// Stub notifier: build() returns a fixed state without touching auth/network.
class _StubConsent extends UserConsentNotifier {
  _StubConsent(this._s);
  final UserConsent _s;
  @override
  UserConsent build() => _s;
}

Widget _wrap(UserConsent state, Widget child) => ProviderScope(
      overrides: [
        userConsentProvider.overrideWith(() => _StubConsent(state)),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('banner shows when undecided + authed', (tester) async {
    await tester.pumpWidget(
      _wrap(const UserConsent(authed: true), const ConsentBanner()),
    );
    expect(find.text('consent.accept'), findsOneWidget);
    expect(find.text('consent.decline'), findsOneWidget);
  });

  testWidgets('banner hidden when decided', (tester) async {
    await tester.pumpWidget(
      _wrap(
        UserConsent(authed: true, analyticsEnabled: true, consentedAt: DateTime(2026)),
        const ConsentBanner(),
      ),
    );
    expect(find.text('consent.accept'), findsNothing);
  });

  testWidgets('banner hidden for guest', (tester) async {
    await tester.pumpWidget(
      _wrap(const UserConsent(), const ConsentBanner()),
    );
    expect(find.byType(ConsentBanner), findsOneWidget); // mounted
    expect(find.text('consent.accept'), findsNothing); // but renders nothing
  });

  testWidgets('banner hidden while loading', (tester) async {
    await tester.pumpWidget(
      _wrap(const UserConsent(authed: true, loading: true), const ConsentBanner()),
    );
    expect(find.text('consent.accept'), findsNothing);
  });

  testWidgets('privacy settings renders toggle + delete + policy link',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserConsent(authed: true, analyticsEnabled: true),
        const PrivacySettingsScreen(),
      ),
    );
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('consent.delete_all'), findsOneWidget);
    expect(find.text('consent.read_policy'), findsOneWidget);
    expect(find.text('consent.setting_on_help'), findsOneWidget);
  });

  testWidgets('settings delete shows confirmation dialog', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserConsent(authed: true),
        const PrivacySettingsScreen(),
      ),
    );
    await tester.tap(find.text('consent.delete_all'));
    await tester.pumpAndSettle();
    expect(find.text('consent.delete_confirm_body'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
