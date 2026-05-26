/** Known-good seeded data on staging — do not change without re-seeding. */
export const PHONE = "5551234567"; // UI format (10 digits, no +90)
export const PHONE_E164 = "+905551234567";
export const OTP = "123456"; // DEV_OTP_ACCEPT_ANY=true on staging

export const SIPAY_CARD = {
  number: "4111 1111 1111 1111",
  expiry: "12/26",
  cvv: "000",
};

export const SIPAY_DECLINED_CARD = {
  number: "4111 1111 1111 1119",
  expiry: "12/26",
  cvv: "000",
};

/** Category used in seed data. Must exist in ref_schema.categories on staging. */
export const SEED_CATEGORY_SLUG = "elektronik";
export const SEED_SEARCH_QUERY = "kulaklik";

/** Turkish copy expected on various pages */
export const COPY = {
  emptyCart: "Sepetiniz boş",
  addToCart: "Sepete Ekle",
  noProducts: "Bu kategoride ürün bulunamadı",
  coinBadgePrefix: "Mopro Coin",
  paymentFailed: "Ödeme başarısız",
  orderReceived: "Sipariş Alındı",
};
