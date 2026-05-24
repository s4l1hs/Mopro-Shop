"use client";

import { Menu, Search, ShoppingCart, User } from "lucide-react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { useCartStore } from "@/store/cart";

export function Header() {
  const t = useTranslations("nav");
  const [mobileOpen, setMobileOpen] = useState(false);
  const itemCount = useCartStore((s) => s.itemCount);

  return (
    <header className="sticky top-0 z-40 w-full border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="mx-auto flex h-14 max-w-7xl items-center gap-4 px-4 sm:px-6 lg:px-8">
        {/* Mobile hamburger */}
        <Button
          variant="ghost"
          size="icon"
          className="lg:hidden"
          onClick={() => setMobileOpen(true)}
          aria-label="Menüyü aç"
        >
          <Menu className="h-5 w-5" />
        </Button>

        {/* Logo */}
        <Link
          href="/"
          className="text-xl font-bold tracking-tight text-primary"
          aria-label="Mopro ana sayfa"
        >
          mopro
        </Link>

        {/* Desktop search (W2 placeholder) */}
        <div className="hidden flex-1 lg:flex">
          <div className="relative w-full max-w-lg">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input
              type="search"
              placeholder={useTranslations("catalog")("search_hint")}
              className="h-9 w-full rounded-md border border-input bg-muted pl-9 pr-3 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              readOnly
            />
          </div>
        </div>

        <div className="ml-auto flex items-center gap-1">
          {/* Desktop nav links */}
          <nav className="hidden items-center gap-1 lg:flex">
            <Button variant="ghost" size="sm" asChild>
              <Link href="/">{t("home")}</Link>
            </Button>
            <Button variant="ghost" size="sm" asChild>
              <Link href="/categories">{t("categories")}</Link>
            </Button>
            <Button variant="ghost" size="sm" asChild>
              <Link href="/account/wallet">{t("wallet")}</Link>
            </Button>
          </nav>

          {/* Cart */}
          <Button variant="ghost" size="icon" asChild aria-label={t("cart")}>
            <Link href="/cart" className="relative">
              <ShoppingCart className="h-5 w-5" />
              {itemCount > 0 && (
                <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-[10px] font-bold text-primary-foreground">
                  {itemCount > 99 ? "99+" : itemCount}
                </span>
              )}
            </Link>
          </Button>

          {/* Account */}
          <Button variant="ghost" size="icon" asChild aria-label={t("profile")}>
            <Link href="/account">
              <User className="h-5 w-5" />
            </Link>
          </Button>
        </div>
      </div>

      {/* Mobile nav sheet */}
      <Sheet open={mobileOpen} onOpenChange={setMobileOpen}>
        <SheetContent side="left">
          <SheetHeader>
            <SheetTitle className="text-primary">mopro</SheetTitle>
          </SheetHeader>
          <nav className="mt-6 flex flex-col gap-1">
            {[
              { href: "/", label: t("home") },
              { href: "/categories", label: t("categories") },
              { href: "/account/wallet", label: t("wallet") },
              { href: "/account", label: t("profile") },
            ].map(({ href, label }) => (
              <Button
                key={href}
                variant="ghost"
                className="justify-start"
                asChild
                onClick={() => setMobileOpen(false)}
              >
                <Link href={href}>{label}</Link>
              </Button>
            ))}
          </nav>
        </SheetContent>
      </Sheet>
    </header>
  );
}
