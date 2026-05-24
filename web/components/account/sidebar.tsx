"use client";

import {
  Coins,
  CreditCard,
  Heart,
  LayoutDashboard,
  LogOut,
  MapPin,
  Package,
  Shield,
  User,
} from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { toast } from "sonner";
import { apiFetch } from "@/lib/api-client";
import { useCartStore } from "@/store/cart";
import { cn } from "@/lib/utils";

interface NavItem {
  href: string;
  icon: React.ElementType;
  label: string;
  exact?: boolean;
}

const NAV_ITEMS: NavItem[] = [
  { href: "/account", icon: LayoutDashboard, label: "Hesabım", exact: true },
  { href: "/account/orders", icon: Package, label: "Siparişlerim" },
  { href: "/account/cashback", icon: Coins, label: "Cashback Cüzdanım" },
  { href: "/account/addresses", icon: MapPin, label: "Adreslerim" },
  { href: "/account/cards", icon: CreditCard, label: "Kayıtlı Kartlarım" },
  { href: "/account/favorites", icon: Heart, label: "Favorilerim" },
  { href: "/account/profile", icon: User, label: "Profil Bilgilerim" },
  { href: "/account/security", icon: Shield, label: "Güvenlik" },
];

function useLocalePathname() {
  const rawPathname = usePathname();
  return rawPathname.replace(/^\/(tr|en)(\/|$)/, "/").replace(/\/$/, "") || "/";
}

function isActive(href: string, pathname: string, exact?: boolean): boolean {
  if (exact) return pathname === href;
  return pathname === href || pathname.startsWith(href + "/");
}

export function AccountSidebar() {
  const pathname = useLocalePathname();
  const router = useRouter();

  const handleLogout = async () => {
    try {
      await apiFetch<void>("/auth/logout", { method: "POST" });
    } catch {
      // ignore errors — clear state anyway
    }
    useCartStore.getState().clearCart();
    router.push("/");
    toast.success("Çıkış yapıldı");
  };

  return (
    <nav aria-label="Hesap menüsü" className="space-y-1">
      {NAV_ITEMS.map(({ href, icon: Icon, label, exact }) => {
        const active = isActive(href, pathname, exact);
        return (
          <Link
            key={href}
            href={href}
            className={cn(
              "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
              active
                ? "bg-primary/10 text-primary border-l-4 border-primary rounded-l-none pl-2"
                : "text-muted-foreground hover:text-foreground hover:bg-accent border-l-4 border-transparent rounded-l-none pl-2",
            )}
            aria-current={active ? "page" : undefined}
          >
            <Icon className="h-4 w-4 shrink-0" />
            {label}
          </Link>
        );
      })}

      <button
        type="button"
        onClick={handleLogout}
        className="flex w-full items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors border-l-4 border-transparent rounded-l-none pl-2"
      >
        <LogOut className="h-4 w-4 shrink-0" />
        Çıkış yap
      </button>
    </nav>
  );
}

export function AccountMobileTabStrip() {
  const pathname = useLocalePathname();
  const router = useRouter();

  const handleLogout = async () => {
    try {
      await apiFetch<void>("/auth/logout", { method: "POST" });
    } catch {
      // ignore errors
    }
    useCartStore.getState().clearCart();
    router.push("/");
    toast.success("Çıkış yapıldı");
  };

  return (
    <div className="flex gap-1 overflow-x-auto scrollbar-hide px-4 py-2">
      {NAV_ITEMS.map(({ href, icon: Icon, label, exact }) => {
        const active = isActive(href, pathname, exact);
        return (
          <Link
            key={href}
            href={href}
            className={cn(
              "flex shrink-0 items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-colors",
              active
                ? "bg-primary text-primary-foreground"
                : "bg-muted text-muted-foreground hover:text-foreground",
            )}
            aria-current={active ? "page" : undefined}
          >
            <Icon className="h-3.5 w-3.5 shrink-0" />
            {label}
          </Link>
        );
      })}
      <button
        type="button"
        onClick={handleLogout}
        className="flex shrink-0 items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium whitespace-nowrap bg-muted text-muted-foreground hover:text-destructive transition-colors"
      >
        <LogOut className="h-3.5 w-3.5 shrink-0" />
        Çıkış
      </button>
    </div>
  );
}
