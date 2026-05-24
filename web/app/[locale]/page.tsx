import { useTranslations } from "next-intl";
import type { Metadata } from "next";

export const revalidate = 60;

export const metadata: Metadata = {
  title: "Mopro — Süresiz Cashback ile Alışveriş",
  description:
    "Mopro'da alışveriş yap, her ay Mopro Coin kazan — süresiz. Türkiye'nin cashback marketplacı.",
};

export default function HomePage() {
  const t = useTranslations("home");
  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
      {/* W2: banners, categories grid, product carousel */}
      <p className="mt-4 text-muted-foreground">Kategoriler ve ürünler yakında…</p>
    </div>
  );
}
