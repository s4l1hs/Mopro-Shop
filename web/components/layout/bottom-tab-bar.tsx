"use client";

// TODO(U6): itemCount is always 0 until U6 wires API-synced cart state
// into useCartStore. Replace with: useCartStore((s) => s.syncFromApi()).

import { Grid2x2, Home, ShoppingCart, User, Wallet } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { useCartStore } from "@/store/cart";

interface TabItem {
  href: string;
  icon: LucideIcon;
  label: string;
  showBadge?: boolean;
}

const TAB_ITEMS: TabItem[] = [
  { href: "/", icon: Home, label: "Ana Sayfa" },
  { href: "/categories", icon: Grid2x2, label: "Kategoriler" },
  { href: "/cart", icon: ShoppingCart, label: "Sepet", showBadge: true },
  { href: "/account/wallet", icon: Wallet, label: "Cüzdan" },
  { href: "/account", icon: User, label: "Profil" },
];

export function BottomTabBar() {
  const rawPathname = usePathname();
  const cartCount = useCartStore((s) => s.itemCount);

  // Strip locale prefix (/tr, /en) to get the app route
  const pathname = rawPathname.replace(/^\/(tr|en)(\/|$)/, "/");

  return (
    <nav
      aria-label="Mobil alt navigasyon"
      className="fixed bottom-0 left-0 right-0 z-40 border-t border-border bg-background/95 backdrop-blur-sm pb-[env(safe-area-inset-bottom)] lg:hidden"
    >
      <div className="flex h-16 items-center justify-around">
        {TAB_ITEMS.map(({ href, icon: Icon, label, showBadge }) => {
          const isActive =
            href === "/" ? pathname === "/" : pathname.startsWith(href);

          return (
            <Link
              key={href}
              href={href}
              className={cn(
                "flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-[10px] font-medium transition-colors",
                isActive
                  ? "text-primary"
                  : "text-muted-foreground hover:text-foreground",
              )}
              aria-current={isActive ? "page" : undefined}
            >
              <span className="relative">
                <Icon className="h-5 w-5" />
                {showBadge && cartCount > 0 && (
                  <span className="absolute -right-1.5 -top-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-primary text-[9px] font-bold text-primary-foreground">
                    {cartCount > 99 ? "99+" : cartCount}
                  </span>
                )}
              </span>
              <span>{label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
