import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/payments/sipay_error_map.dart';

void main() {
  const fallback =
      'Ödeme tamamlanamadı. Lütfen tekrar deneyin veya başka bir kart kullanın.';

  group('SipayErrorMap.get — known codes', () {
    final cases = [
      ('insufficient_funds', 'bakiye'),
      ('card_declined', 'reddedildi'),
      ('3ds_failed', '3D Secure'),
      ('invalid_card', 'hatalı'),
      ('expired_card', 'süresi dolmuş'),
      ('cvv_mismatch', 'CVV'),
      ('issuer_unavailable', 'Banka'),
      ('fraud_suspected', 'Güvenlik'),
      ('amount_limit_exceeded', 'limit'),
      ('rate_limit_exceeded', 'dakika'),
      ('reservation_expired', 'rezervasyon'),
    ];

    for (final (code, needle) in cases) {
      test("code '$code' message contains '$needle'", () {
        final msg = SipayErrorMap.get(code);
        expect(msg.toLowerCase(), contains(needle.toLowerCase()));
      });
    }
  });

  group('SipayErrorMap.get — fallback behaviour', () {
    test('returns fallback for unknown code', () {
      expect(SipayErrorMap.get('totally_unknown_xyz'), fallback);
    });

    test('returns fallback for null', () {
      expect(SipayErrorMap.get(null), fallback);
    });

    test('returns fallback for empty string', () {
      expect(SipayErrorMap.get(''), fallback);
    });

    test("explicit 'unknown' code returns the fallback message", () {
      expect(SipayErrorMap.get('unknown'), fallback);
    });
  });
}
