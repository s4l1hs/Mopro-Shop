import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/payments/sipay_error_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

// `SipayErrorMap.get` resolves via the global `.tr()`, which returns the *key*
// in unit tests (the bundle isn't loaded — see test/core/router/page_title_test).
// We assert code → key mapping + fallback here, and the key → action-guiding
// Turkish copy directly from tr-TR.json.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  const codes = [
    'insufficient_funds',
    'card_declined',
    '3ds_failed',
    'invalid_card',
    'expired_card',
    'cvv_mismatch',
    'issuer_unavailable',
    'fraud_suspected',
    'amount_limit_exceeded',
    'rate_limit_exceeded',
    'reservation_expired',
  ];

  group('SipayErrorMap.get — code → payment.error.sipay key', () {
    for (final code in codes) {
      test("code '$code' → its key", () {
        expect(SipayErrorMap.get(code), 'payment.error.sipay.$code');
      });
    }
  });

  group('SipayErrorMap.get — fallback → unknown key', () {
    const unknownKey = 'payment.error.sipay.unknown';
    test('unknown code', () {
      expect(SipayErrorMap.get('totally_unknown_xyz'), unknownKey);
    });
    test('null', () => expect(SipayErrorMap.get(null), unknownKey));
    test('empty', () => expect(SipayErrorMap.get(''), unknownKey));
    test("explicit 'unknown'", () {
      expect(SipayErrorMap.get('unknown'), unknownKey);
    });
  });

  test('sipay error keys resolve to action-guiding Turkish copy', () {
    final sipay = (((json.decode(
      File('assets/translations/tr-TR.json').readAsStringSync(),
    ) as Map)['payment'] as Map)['error'] as Map)['sipay'] as Map;
    const needles = {
      'insufficient_funds': 'bakiye',
      'card_declined': 'reddedildi',
      '3ds_failed': '3D Secure',
      'invalid_card': 'hatalı',
      'expired_card': 'süresi dolmuş',
      'cvv_mismatch': 'CVV',
      'issuer_unavailable': 'Banka',
      'fraud_suspected': 'Güvenlik',
      'amount_limit_exceeded': 'limit',
      'rate_limit_exceeded': 'dakika',
      'reservation_expired': 'rezervasyon',
    };
    for (final entry in needles.entries) {
      expect(
        (sipay[entry.key] as String).toLowerCase(),
        contains(entry.value.toLowerCase()),
        reason: entry.key,
      );
    }
  });
}
