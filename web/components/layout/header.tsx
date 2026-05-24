"use client";

import { Heart, Search, ShoppingCart } from "lucide-react";
import Link from "next/link";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { useCartStore } from "@/store/cart";
import { cn } from "@/lib/utils";
import { CategoryMegaMenu } from "./category-mega-menu";
import { HeaderSearch } from "./header-search";
import { HeaderUserMenu } from "./header-user-menu";
import { MobileNavSheet } from "./mobile-nav-sheet";

export function Header() {
  const [scrolled, setScrolled] = useState(false);
  const cartCount = useCartStore((s) => s.itemCount);

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 0);
    // Set initial state in case page loads mid-scroll
    handleScroll();
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <header
      className={cn(
        "sticky top-0 z-50 w-full bg-background/95 backdrop-blur-sm transition-all duration-150",
        scrolled
          ? "border-b border-border shadow-sm"
          : "border-b border-transparent",
      )}
    >
      {/* ===== MAIN BAR ===== */}
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-14 lg:h-16 items-center gap-2 sm:gap-3">
          {/* Mobile: hamburger sheet (self-contained trigger) */}
          <MobileNavSheet />

          {/* Logo */}
          <Link
            href="/"
            className="shrink-0 text-xl font-bold tracking-tight text-primary"
            aria-label="Mopro ana sayfa"
          >
            mopro
          </Link>

          {/* Desktop: flex-grow search bar */}
          <div className="hidden lg:flex flex-1 mx-3">
            <HeaderSearch className="w-full max-w-xl" />
          </div>

          {/* Spacer to push action icons right on mobile */}
          <div className="flex-1 lg:hidden" />

          {/* Action icons */}
          <div className="flex items-center gap-0.5">
            {/* Desktop: ThemeToggle */}
            <ThemeToggle className="hidden lg:inline-flex" />

            {/* Mobile: search navigates to /search page */}
            <Button
              variant="ghost"
              size="icon"
              aria-label="Ara"
              className="lg:hidden"
              asChild
            >
              <Link href="/search">
                <Search className="h-5 w-5" />
              </Link>
            </Button>

            {/* Wishlist (stub — U5 adds wishlist) */}
            <Button variant="ghost" size="icon" aria-label="Favoriler" asChild>
              <Link href="/account/wishlist">
                <Heart className="h-5 w-5" />
              </Link>
            </Button>

            {/* Cart with badge */}
            <Button variant="ghost" size="icon" aria-label="Sepet" asChild>
              <Link href="/cart" className="relative">
                <ShoppingCart className="h-5 w-5" />
                {cartCount > 0 && (
                  <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-[9px] font-bold text-primary-foreground">
                    {cartCount > 99 ? "99+" : cartCount}
                  </span>
                )}
              </Link>
            </Button>

            {/* Desktop: user menu (login or account dropdown) */}
            <HeaderUserMenu className="hidden lg:flex" />
          </div>
        </div>
      </div>

      {/* ===== CATEGORY STRIP (desktop only) ===== */}
      <div className="hidden lg:block border-t border-border/40">
        <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <CategoryMegaMenu />
        </div>
      </div>
    </header>
  );
}
