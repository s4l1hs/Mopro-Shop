export const SIPAY_ERROR_MESSAGES: Record<string, string> = {
  insufficient_funds:
    "Kartınızda yeterli bakiye bulunmuyor. Lütfen başka bir kart deneyin.",
  card_declined:
    "Kartınız ret etti. Lütfen bankanızla iletişime geçin.",
  "3ds_failed":
    "3D Secure doğrulaması başarısız oldu. Lütfen tekrar deneyin.",
  invalid_card:
    "Kart bilgileri hatalı. Lütfen kontrol edip tekrar deneyin.",
  expired_card:
    "Kartınızın süresi dolmuş.",
  cvv_mismatch:
    "CVV kodu hatalı.",
  issuer_unavailable:
    "Banka şu an yanıt vermiyor. Birkaç dakika sonra tekrar deneyin.",
  fraud_suspected:
    "Güvenlik kontrolü nedeniyle işlem reddedildi. Bankanızla iletişime geçin.",
  amount_limit_exceeded:
    "Günlük kart limiti aşıldı.",
  rate_limit_exceeded:
    "Çok fazla ödeme denemesi. Lütfen 1 dakika sonra tekrar deneyin.",
  reservation_expired:
    "Sepet rezervasyonunun süresi doldu. Lütfen tekrar deneyin.",
  unknown:
    "Ödeme tamamlanamadı. Lütfen tekrar deneyin veya başka bir kart kullanın.",
};

export function getSipayErrorMessage(code: string | undefined | null): string {
  if (!code) return SIPAY_ERROR_MESSAGES["unknown"] ?? "";
  return SIPAY_ERROR_MESSAGES[code] ?? SIPAY_ERROR_MESSAGES["unknown"] ?? "";
}
