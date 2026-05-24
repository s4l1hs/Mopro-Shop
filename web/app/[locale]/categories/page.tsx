import { useTranslations } from "next-intl";
import type { Metadata } from "next";

export const revalidate = 60;

export const metadata: Metadata = {
  title: "Kategoriler — Mopro",
};

export default function KategorilerPage() {
  const t = useTranslations("catalog");
  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <h1 className="text-2xl font-bold tracking-tight">{t("categories")}</h1>
      {/* W2: category grid */}
      <p className="mt-4 text-muted-foreground">Kategoriler yakında…</p>
    </div>
  );
}
