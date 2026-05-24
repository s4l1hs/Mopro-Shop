import { useTranslations } from "next-intl";
import Link from "next/link";

export function Footer() {
  const t = useTranslations("footer");

  return (
    <footer className="mt-auto border-t border-border bg-background">
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <div className="flex flex-col items-center gap-4 sm:flex-row sm:justify-between">
          <p className="text-center text-xs text-muted-foreground">{t("kvkk")}</p>
          <nav className="flex gap-4 text-xs text-muted-foreground">
            <Link href="/kvkk" className="hover:text-foreground transition-colors">
              {t("privacy")}
            </Link>
            <Link href="/kullanim-kosullari" className="hover:text-foreground transition-colors">
              {t("terms")}
            </Link>
          </nav>
        </div>
        <p className="mt-4 text-center text-xs text-muted-foreground">{t("rights")}</p>
      </div>
    </footer>
  );
}
