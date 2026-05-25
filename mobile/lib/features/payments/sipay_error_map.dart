class SipayErrorMap {
  const SipayErrorMap._();

  static const Map<String, String> _messages = {
    'insufficient_funds':
        'Kartınızda yeterli bakiye bulunmuyor. Lütfen başka bir kart deneyin.',
    'card_declined': 'Kartınız reddedildi. Lütfen bankanızla iletişime geçin.',
    '3ds_failed': '3D Secure doğrulaması başarısız oldu. Lütfen tekrar deneyin.',
    'invalid_card': 'Kart bilgileri hatalı. Lütfen kontrol edip tekrar deneyin.',
    'expired_card': 'Kartınızın süresi dolmuş.',
    'cvv_mismatch': 'CVV kodu hatalı.',
    'issuer_unavailable':
        'Banka şu an yanıt vermiyor. Birkaç dakika sonra tekrar deneyin.',
    'fraud_suspected':
        'Güvenlik kontrolü nedeniyle işlem reddedildi. Bankanızla iletişime geçin.',
    'amount_limit_exceeded': 'Günlük kart limiti aşıldı.',
    'rate_limit_exceeded':
        'Çok fazla ödeme denemesi. Lütfen 1 dakika sonra tekrar deneyin.',
    'reservation_expired':
        'Sepet rezervasyonunun süresi doldu. Lütfen tekrar deneyin.',
    'unknown':
        'Ödeme tamamlanamadı. Lütfen tekrar deneyin veya başka bir kart kullanın.',
  };

  static const String _fallback =
      'Ödeme tamamlanamadı. Lütfen tekrar deneyin veya başka bir kart kullanın.';

  static String get(String? code) {
    if (code == null || code.isEmpty) return _fallback;
    return _messages[code] ?? _fallback;
  }
}
