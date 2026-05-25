import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/checkout/presentation/sipay_webview_screen.dart';

void main() {
  group('SipayResult.fromParams', () {
    test('status=success → SipayResultSuccess with invoiceId', () {
      final result = SipayResult.fromParams({
        'status': 'success',
        'invoice_id': 'inv-abc-123',
      });
      expect(result, isA<SipayResultSuccess>());
      expect((result as SipayResultSuccess).invoiceId, 'inv-abc-123');
    });

    test('status=success with empty invoice_id defaults to empty string', () {
      final result = SipayResult.fromParams({'status': 'success'});
      expect(result, isA<SipayResultSuccess>());
      expect((result as SipayResultSuccess).invoiceId, '');
    });

    test('status=failed → SipayResultFailed with reason', () {
      final result = SipayResult.fromParams({
        'status': 'failed',
        'reason': 'insufficient_funds',
      });
      expect(result, isA<SipayResultFailed>());
      expect((result as SipayResultFailed).reason, 'insufficient_funds');
    });

    test('status=failed falls back to error_code field', () {
      final result = SipayResult.fromParams({
        'status': 'failed',
        'error_code': 'card_declined',
      });
      expect((result as SipayResultFailed).reason, 'card_declined');
    });

    test('status=failed with no reason → payment_failed default', () {
      final result = SipayResult.fromParams({'status': 'failed'});
      expect((result as SipayResultFailed).reason, 'payment_failed');
    });

    test('status=cancelled → SipayResultCancelled', () {
      final result = SipayResult.fromParams({'status': 'cancelled'});
      expect(result, isA<SipayResultCancelled>());
    });

    test('unknown status → SipayResultError', () {
      final result = SipayResult.fromParams({'status': 'weird_value'});
      expect(result, isA<SipayResultError>());
      expect((result as SipayResultError).message, contains('weird_value'));
    });

    test('null status → SipayResultError', () {
      final result = SipayResult.fromParams({});
      expect(result, isA<SipayResultError>());
    });
  });
}
