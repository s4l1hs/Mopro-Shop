import { NextIntlClientProvider } from "next-intl";
import { getMessages } from "next-intl/server";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { Footer } from "@/components/layout/footer";
import { Header } from "@/components/layout/header";
import { MobileNav } from "@/components/layout/mobile-nav";
import { Providers } from "@/components/providers";
import { routing } from "@/i18n/routing";
import "@/app/globals.css";

interface Props {
  children: ReactNode;
  params: Promise<{ locale: string }>;
}

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({ children, params }: Props) {
  const { locale } = await params;

  if (!(routing.locales as readonly string[]).includes(locale)) {
    notFound();
  }

  const messages = await getMessages();

  return (
    <html lang={locale} suppressHydrationWarning>
      <head />
      <body className="min-h-screen flex flex-col bg-background text-foreground antialiased">
        <NextIntlClientProvider messages={messages}>
          <Providers>
            <Header />
            <main className="flex-1 pb-20 lg:pb-0">{children}</main>
            <Footer />
            <MobileNav />
          </Providers>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
