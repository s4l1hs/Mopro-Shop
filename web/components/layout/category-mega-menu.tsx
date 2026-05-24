"use client";

import { ChevronDown } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { buildCategoryTree, useCategories } from "@/lib/catalog/categories-cache";
import { cn } from "@/lib/utils";

const STATIC_NAV = [
  { label: "Yeni Gelenler", href: "/categories?sort=newest" },
  { label: "Çok Satanlar", href: "/categories?sort=bestsellers" },
  { label: "İndirimler", href: "/categories?filter=discounts" },
] as const;

export function CategoryMegaMenu() {
  const [open, setOpen] = useState(false);
  const closeTimeout = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const { data: categories, isLoading } = useCategories();
  const tree = categories ? buildCategoryTree(categories) : [];

  // Clean up timer on unmount
  useEffect(() => () => clearTimeout(closeTimeout.current), []);

  const handleMouseEnter = () => {
    clearTimeout(closeTimeout.current);
    setOpen(true);
  };

  const handleMouseLeave = () => {
    closeTimeout.current = setTimeout(() => setOpen(false), 200);
  };

  return (
    <nav aria-label="Kategori navigasyonu" className="flex items-center h-10 text-sm">
      {/* Kategoriler hover mega-menu */}
      <DropdownMenu open={open} onOpenChange={setOpen}>
        <DropdownMenuTrigger asChild>
          <button
            className={cn(
              "inline-flex items-center gap-1 h-10 px-4 font-medium transition-colors",
              "hover:text-primary focus-visible:outline-none focus-visible:text-primary",
              open ? "text-primary" : "text-foreground",
            )}
            onMouseEnter={handleMouseEnter}
            onMouseLeave={handleMouseLeave}
          >
            Kategoriler
            <ChevronDown
              className={cn("h-3.5 w-3.5 transition-transform duration-150", open && "rotate-180")}
            />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          className="w-[860px] max-w-[90vw] p-6 rounded-xl"
          sideOffset={0}
          align="start"
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
          onCloseAutoFocus={(e) => e.preventDefault()}
        >
          {isLoading ? (
            <div className="grid grid-cols-4 gap-5">
              {Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="space-y-2">
                  <Skeleton className="h-4 w-24" />
                  <Skeleton className="h-3 w-20" />
                  <Skeleton className="h-3 w-16" />
                  <Skeleton className="h-3 w-20" />
                </div>
              ))}
            </div>
          ) : tree.length === 0 ? (
            <p className="text-sm text-muted-foreground py-2">Kategoriler yüklenemiyor.</p>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-x-8 gap-y-5">
              {tree.map(({ parent, children }) => (
                <div key={parent.id}>
                  <Link
                    href={`/categories/${parent.slug}`}
                    onClick={() => setOpen(false)}
                    className="block text-sm font-semibold text-foreground hover:text-primary transition-colors mb-2"
                  >
                    {parent.name}
                  </Link>
                  <ul className="space-y-1.5">
                    {children.map((child) => (
                      <li key={child.id}>
                        <Link
                          href={`/categories/${child.slug}`}
                          onClick={() => setOpen(false)}
                          className="text-xs text-muted-foreground hover:text-foreground transition-colors"
                        >
                          {child.name}
                        </Link>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      {/* Static nav links */}
      {STATIC_NAV.map(({ label, href }) => (
        <Link
          key={href}
          href={href}
          className="inline-flex h-10 items-center px-4 font-medium text-foreground hover:text-primary transition-colors"
        >
          {label}
        </Link>
      ))}
    </nav>
  );
}
