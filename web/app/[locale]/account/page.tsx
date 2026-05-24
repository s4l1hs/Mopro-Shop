import { useTranslations } from "next-intl";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Hesabım — Mopro",
};

export default function HesabimPage() {
  const t = useTranslations("nav");
  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <h1 className="text-2xl font-bold tracking-tight">{t("profile")}</h1>
      {/* W4: profile, orders, addresses, cashback plans */}
      <p className="mt-4 text-muted-foreground">Hesap sayfaları yakında…</p>
    </div>
  );
}
