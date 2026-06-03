import 'package:easy_localization/easy_localization.dart';

/// Maps a Sipay failure code to a user-facing, action-guiding message.
///
/// P-014: messages live under the `payment.error.sipay.<code>` i18n keys
/// (tr-TR master + en-US). `get` resolves the code to a key and localises it;
/// unknown/empty codes fall back to `payment.error.sipay.unknown`. The
/// interpolated `'…$known'.tr()` lets the i18n usage analyzer auto-derive the
/// `payment.error.sipay.` prefix, so the keys are covered without per-key
/// `.tr()` call sites.
class SipayErrorMap {
  const SipayErrorMap._();

  /// Known Sipay failure codes (each has a `payment.error.sipay.<code>` key).
  static const Set<String> _codes = {
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
    'unknown',
  };

  static String get(String? code) {
    final known = (code != null && _codes.contains(code)) ? code : 'unknown';
    return 'payment.error.sipay.$known'.tr();
  }
}
