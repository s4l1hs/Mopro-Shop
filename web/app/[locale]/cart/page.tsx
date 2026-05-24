import { useTranslations } from "next-intl";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Sepetim — Mopro",
};

export default function SepetPage() {
  const t = useTranslations("cart");
  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
      {/* W3: cart items, checkout CTA */}
      <p className="mt-4 text-muted-foreground">{t("empty_title")}</p>
    </div>
  );
}
