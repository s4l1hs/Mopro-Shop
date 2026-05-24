"use client";

import { ChevronDown, CreditCard } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";

const FOOTER_SECTIONS = [
  {
    id: "about",
    title: "Mopro Hakkında",
    links: [
      { label: "Hakkımızda", href: "/about" },
      { label: "Kariyer", href: "/careers" },
      { label: "Blog", href: "/blog" },
    ],
  },
  {
    id: "help",
    title: "Yardım",
    links: [
      { label: "Sıkça Sorulan Sorular", href: "/faq" },
      { label: "İletişim", href: "/contact" },
      { label: "İade & Değişim", href: "/returns" },
    ],
  },
  {
    id: "legal",
    title: "Hukuk",
    links: [
      { label: "Gizlilik Politikası", href: "/privacy" },
      { label: "Kullanım Koşulları", href: "/terms" },
      { label: "KVKK", href: "/kvkk" },
      { label: "Çerez Politikası", href: "/cookie-policy" },
    ],
  },
  {
    id: "social",
    title: "Bizi Takip Et",
    links: [
      { label: "Instagram", href: "https://instagram.com/moproshop" },
      { label: "Twitter / X", href: "https://twitter.com/moproshop" },
      { label: "LinkedIn", href: "https://linkedin.com/company/moproshop" },
    ],
  },
] as const;

function FooterLinkList({
  links,
}: {
  links: readonly { label: string; href: string }[];
}) {
  return (
    <ul className="space-y-2.5">
      {links.map(({ label, href }) => (
        <li key={href}>
          <Link
            href={href}
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            {label}
          </Link>
        </li>
      ))}
    </ul>
  );
}

export function Footer() {
  const [openSection, setOpenSection] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const toggle = (id: string) =>
    setOpenSection((prev) => (prev === id ? null : id));

  return (
    <footer className="mt-auto border-t border-border bg-card text-card-foreground">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        {/* ===== DESKTOP: 4-column grid ===== */}
        <div className="hidden lg:grid grid-cols-4 gap-8 py-12">
          {FOOTER_SECTIONS.slice(0, 3).map(({ id, title, links }) => (
            <div key={id}>
              <h3 className="text-sm font-semibold text-foreground mb-4">{title}</h3>
              <FooterLinkList links={links} />
            </div>
          ))}

          {/* Column 4: Social + Newsletter */}
          <div>
            <h3 className="text-sm font-semibold text-foreground mb-4">
              Bizi Takip Et
            </h3>
            <FooterLinkList links={FOOTER_SECTIONS[3].links} />

            <div className="mt-6">
              <h4 className="text-xs font-semibold text-foreground mb-2.5">
                E-Bülten
              </h4>
              <div className="flex gap-2">
                <Input
                  type="email"
                  placeholder="E-posta adresiniz"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="h-9 text-xs"
                />
                <Button
                  size="sm"
                  onClick={() => toast("Yakında — e-bülten aboneliği")}
                  className="shrink-0 h-9 px-3 text-xs"
                >
                  Kayıt Ol
                </Button>
              </div>
            </div>
          </div>
        </div>

        {/* ===== MOBILE: accordion ===== */}
        <div className="lg:hidden divide-y divide-border">
          {FOOTER_SECTIONS.map(({ id, title, links }) => (
            <div key={id}>
              <button
                type="button"
                onClick={() => toggle(id)}
                className="flex w-full items-center justify-between py-4 text-sm font-semibold text-foreground"
              >
                {title}
                <ChevronDown
                  className={cn(
                    "h-4 w-4 text-muted-foreground transition-transform duration-200",
                    openSection === id && "rotate-180",
                  )}
                />
              </button>
              <div
                className={cn(
                  "overflow-hidden transition-all duration-200",
                  openSection === id ? "max-h-64 pb-4" : "max-h-0",
                )}
              >
                <FooterLinkList links={links} />
              </div>
            </div>
          ))}

          {/* Mobile newsletter */}
          <div className="py-4">
            <p className="text-sm font-semibold text-foreground mb-3">E-Bülten</p>
            <div className="flex gap-2">
              <Input
                type="email"
                placeholder="E-posta adresiniz"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="h-9 text-xs"
              />
              <Button
                size="sm"
                onClick={() => toast("Yakında — e-bülten aboneliği")}
                className="shrink-0 h-9 px-3 text-xs"
              >
                Kayıt Ol
              </Button>
            </div>
          </div>
        </div>

        {/* ===== BOTTOM STRIP ===== */}
        <div className="border-t border-border py-5 flex flex-col sm:flex-row items-center justify-between gap-3">
          <div className="flex items-center gap-2 text-muted-foreground">
            <CreditCard className="h-6 w-8 shrink-0" aria-hidden="true" />
            <span className="text-xs">Güvenli ödeme</span>
          </div>
          <p className="text-xs text-muted-foreground text-center">
            © 2026 Mopro Ticaret A.Ş. Tüm hakları saklıdır.
          </p>
        </div>
      </div>
    </footer>
  );
}
