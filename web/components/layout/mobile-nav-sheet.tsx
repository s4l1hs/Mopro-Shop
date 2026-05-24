"use client";

import { ChevronDown, LogIn, LogOut, Menu, Search, User } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type ReactNode, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { useSession } from "@/lib/auth/use-session";
import { useCategories } from "@/lib/catalog/categories-cache";
import { cn } from "@/lib/utils";

interface AccordionItemProps {
  title: string;
  isOpen: boolean;
  onToggle: () => void;
  children: ReactNode;
}

function AccordionItem({ title, isOpen, onToggle, children }: AccordionItemProps) {
  return (
    <div>
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center justify-between py-3 text-sm font-medium text-foreground hover:text-primary transition-colors"
      >
        {title}
        <ChevronDown
          className={cn(
            "h-4 w-4 text-muted-foreground transition-transform duration-200",
            isOpen && "rotate-180",
          )}
        />
      </button>
      <div
        className={cn(
          "overflow-hidden transition-all duration-200",
          isOpen ? "max-h-72 pb-3" : "max-h-0",
        )}
      >
        {children}
      </div>
    </div>
  );
}

export function MobileNavSheet() {
  const [open, setOpen] = useState(false);
  const [openSection, setOpenSection] = useState<string | null>(null);
  const { isAuthenticated } = useSession();
  const { data: categories } = useCategories();
  const router = useRouter();

  const close = () => {
    setOpen(false);
    setOpenSection(null);
  };

  const topCategories = (categories ?? [])
    .filter((c) => c.parent_id === null)
    .slice(0, 12);

  const handleLogout = async () => {
    close();
    await fetch("/api/auth/logout", { method: "POST" });
    router.push("/login");
    router.refresh();
  };

  const toggleSection = (id: string) =>
    setOpenSection((prev) => (prev === id ? null : id));

  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger asChild>
        <Button variant="ghost" size="icon" aria-label="Menüyü aç" className="lg:hidden">
          <Menu className="h-5 w-5" />
        </Button>
      </SheetTrigger>

      <SheetContent side="left" className="flex flex-col p-0 w-80 max-w-[85vw]">
        {/* Logo */}
        <SheetHeader className="px-5 pt-5 pb-4 border-b border-border">
          <SheetTitle>
            <Link href="/" onClick={close} className="text-xl font-bold text-primary">
              mopro
            </Link>
          </SheetTitle>
        </SheetHeader>

        <div className="flex-1 overflow-y-auto">
          {/* User section */}
          <div className="px-5 py-4 border-b border-border">
            {isAuthenticated ? (
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                  <User className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <p className="text-sm font-medium text-foreground">Hesabım</p>
                  <Link
                    href="/account"
                    onClick={close}
                    className="text-xs text-primary hover:underline underline-offset-2"
                  >
                    Profilimi Gör →
                  </Link>
                </div>
              </div>
            ) : (
              <Button asChild className="w-full" onClick={close}>
                <Link href="/login">
                  <LogIn className="h-4 w-4 mr-2" />
                  Giriş Yap / Kayıt Ol
                </Link>
              </Button>
            )}
          </div>

          {/* Search */}
          <div className="px-5 py-3 border-b border-border">
            <div className="flex items-center gap-2 h-9 px-3 rounded-full bg-secondary text-sm">
              <Search className="h-4 w-4 text-muted-foreground shrink-0" />
              <input
                type="search"
                placeholder="Ürün, kategori veya marka ara..."
                className="flex-1 bg-transparent outline-none text-sm placeholder:text-muted-foreground"
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    const q = (e.target as HTMLInputElement).value.trim();
                    if (q) {
                      close();
                      router.push(`/search?q=${encodeURIComponent(q)}`);
                    }
                  }
                }}
              />
            </div>
          </div>

          {/* Primary nav links */}
          <nav className="px-5 py-2 border-b border-border">
            {[
              { href: "/", label: "Ana Sayfa" },
              { href: "/account/wallet", label: "Cüzdanım" },
              { href: "/account/orders", label: "Siparişlerim" },
            ].map(({ href, label }) => (
              <Link
                key={href}
                href={href}
                onClick={close}
                className="flex h-10 items-center text-sm font-medium text-foreground hover:text-primary transition-colors"
              >
                {label}
              </Link>
            ))}
          </nav>

          {/* Categories accordion */}
          <div className="px-5 border-b border-border">
            <AccordionItem
              title="Kategoriler"
              isOpen={openSection === "categories"}
              onToggle={() => toggleSection("categories")}
            >
              {topCategories.length === 0 ? (
                <p className="text-xs text-muted-foreground py-1">
                  Kategoriler yükleniyor...
                </p>
              ) : (
                <div className="grid grid-cols-2 gap-x-4 gap-y-0.5">
                  {topCategories.map((cat) => (
                    <Link
                      key={cat.id}
                      href={`/categories/${cat.slug}`}
                      onClick={close}
                      className="py-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors truncate"
                    >
                      {cat.name}
                    </Link>
                  ))}
                </div>
              )}
            </AccordionItem>
          </div>

          {/* Help accordion */}
          <div className="px-5 border-b border-border">
            <AccordionItem
              title="Yardım"
              isOpen={openSection === "help"}
              onToggle={() => toggleSection("help")}
            >
              <div className="flex flex-col">
                {[
                  { href: "/faq", label: "Sıkça Sorulan Sorular" },
                  { href: "/contact", label: "İletişim" },
                  { href: "/returns", label: "İade & Değişim" },
                ].map(({ href, label }) => (
                  <Link
                    key={href}
                    href={href}
                    onClick={close}
                    className="py-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
                  >
                    {label}
                  </Link>
                ))}
              </div>
            </AccordionItem>
          </div>

          {/* Logout */}
          {isAuthenticated && (
            <div className="px-5 py-4">
              <button
                type="button"
                onClick={handleLogout}
                className="flex items-center gap-2 text-sm text-destructive hover:text-destructive/80 transition-colors"
              >
                <LogOut className="h-4 w-4" />
                Çıkış Yap
              </button>
            </div>
          )}
        </div>

        {/* Theme toggle — pinned to bottom */}
        <div className="border-t border-border px-5 py-4 flex items-center justify-between">
          <span className="text-sm text-muted-foreground">Açık / Koyu tema</span>
          <ThemeToggle />
        </div>
      </SheetContent>
    </Sheet>
  );
}
