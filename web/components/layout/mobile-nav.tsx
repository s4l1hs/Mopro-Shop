"use client";

import { Grid2x2, Home, ShoppingCart, User, Wallet } from "lucide-react";
import { useTranslations } from "next-intl";
import type { LucideIcon } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useCartStore } from "@/store/cart";

interface NavItem {
  href: string;
  icon: LucideIcon;
  labelKey: "home" | "categories" | "cart" | "wallet" | "profile";
  showBadge?: boolean;
}

const navItems: NavItem[] = [
  { href: "/", icon: Home, labelKey: "home" },
  { href: "/kategoriler", icon: Grid2x2, labelKey: "categories" },
  { href: "/sepet", icon: ShoppingCart, labelKey: "cart", showBadge: true },
  { href: "/hesabim/cuzdanim", icon: Wallet, labelKey: "wallet" },
  { href: "/hesabim", icon: User, labelKey: "profile" },
];

export function MobileNav() {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const itemCount = useCartStore((s) => s.itemCount);

  return (
    <nav
      aria-label="Mobil alt navigasyon"
      className="fixed bottom-0 left-0 right-0 z-40 border-t border-border bg-background pb-safe lg:hidden"
    >
      <div className="flex h-16 items-center justify-around">
        {navItems.map(({ href, icon: Icon, labelKey, showBadge }) => {
          const isActive = pathname === href || (href !== "/" && pathname.startsWith(href));
          return (
            <Link
              key={href}
              href={href}
              className={cn(
                "flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-[10px] font-medium transition-colors",
                isActive ? "text-primary" : "text-muted-foreground hover:text-foreground",
              )}
              aria-current={isActive ? "page" : undefined}
            >
              <span className="relative">
                <Icon className="h-5 w-5" />
                {showBadge && itemCount > 0 && (
                  <span className="absolute -right-1.5 -top-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-[9px] font-bold text-primary-foreground">
                    {itemCount > 99 ? "99+" : itemCount}
                  </span>
                )}
              </span>
              <span>{t(labelKey)}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
