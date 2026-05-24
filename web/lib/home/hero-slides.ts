export interface HeroSlide {
  id: string;
  title: string;
  subtitle: string;
  cta: { label: string; href: string };
  bgClass: string;
}

export const HERO_SLIDES: HeroSlide[] = [
  {
    id: "cashback",
    title: "Her Alışverişe Süresiz Cashback",
    subtitle: "Satın aldıktan sonra her ay Mopro Coin kazan — sonsuza kadar.",
    cta: { label: "Keşfet", href: "/categories" },
    bgClass: "bg-gradient-to-br from-primary to-primary/70",
  },
  {
    id: "new-arrivals",
    title: "Bu Haftanın Yeni Ürünleri",
    subtitle: "Teknoloji, moda ve daha fazlası — her gün yüzlerce yeni ürün.",
    cta: { label: "Yeni Gelenler", href: "/categories?sort=newest" },
    bgClass: "bg-gradient-to-r from-primary/90 to-primary/60",
  },
  {
    id: "bestsellers",
    title: "Çok Satanlar — Bu Hafta",
    subtitle: "En çok tercih edilen ürünleri keşfedin.",
    cta: { label: "Çok Satanlar", href: "/categories?sort=bestsellers" },
    bgClass: "bg-gradient-to-bl from-primary/85 to-primary/55",
  },
  {
    id: "free-shipping",
    title: "Ücretsiz Kargo",
    subtitle: "150 TL üzeri tüm siparişlerde ücretsiz teslimat.",
    cta: { label: "Alışverişe Başla", href: "/categories" },
    bgClass: "bg-gradient-to-tr from-primary to-primary/75",
  },
];
