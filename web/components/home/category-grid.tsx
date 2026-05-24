"use client";

import {
  Baby,
  BookOpen,
  Car,
  Dumbbell,
  Flower2,
  Gamepad2,
  Home,
  Laptop,
  Monitor,
  Music,
  Package,
  Shirt,
  ShoppingBag,
  Sparkles,
  UtensilsCrossed,
  Watch,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import Link from "next/link";
import { Skeleton } from "@/components/ui/skeleton";
import { useCategories } from "@/lib/catalog/categories-cache";

const SLUG_ICON_MAP: Record<string, LucideIcon> = {
  elektronik: Laptop,
  bilgisayar: Monitor,
  telefon: Laptop,
  "ev-yasam": Home,
  giyim: Shirt,
  "spor-outdoor": Dumbbell,
  oyun: Gamepad2,
  muzik: Music,
  "anne-bebek": Baby,
  kozmetik: Sparkles,
  kitap: BookOpen,
  otomotiv: Car,
  "kisisel-bakim": Flower2,
  mutfak: UtensilsCrossed,
  saat: Watch,
  moda: ShoppingBag,
};

function getIcon(slug: string): LucideIcon {
  const direct = SLUG_ICON_MAP[slug];
  if (direct) return direct;
  const rootWord = slug.split("-")[0] ?? slug;
  const matchKey = Object.keys(SLUG_ICON_MAP).find(
    (k) => k.startsWith(rootWord) || k.split("-")[0] === rootWord,
  );
  return (matchKey ? SLUG_ICON_MAP[matchKey] : undefined) ?? Package;
}

interface CategoryGridProps {
  limit?: number;
}

export function CategoryGrid({ limit = 8 }: CategoryGridProps) {
  const { data: categories, isLoading } = useCategories();
  const topCats = (categories ?? []).filter((c) => c.parent_id === null).slice(0, limit);

  if (isLoading) {
    return (
      <div className="grid grid-cols-4 md:grid-cols-8 gap-3">
        {Array.from({ length: limit }).map((_, i) => (
          <div key={i} className="flex flex-col items-center gap-2">
            <Skeleton className="h-14 w-14 rounded-xl" />
            <Skeleton className="h-3 w-14 rounded" />
          </div>
        ))}
      </div>
    );
  }

  if (topCats.length === 0) return null;

  return (
    <div className="grid grid-cols-4 md:grid-cols-8 gap-3">
      {topCats.map((cat) => {
        const Icon = getIcon(cat.slug);
        return (
          <Link
            key={cat.id}
            href={`/categories/${cat.slug}`}
            className="group flex flex-col items-center gap-2 p-2 rounded-xl hover:bg-accent transition-colors"
          >
            <div className="h-14 w-14 rounded-xl bg-primary/10 flex items-center justify-center group-hover:bg-primary/20 transition-colors">
              <Icon className="h-7 w-7 text-primary" />
            </div>
            <span className="text-xs font-medium text-center text-foreground leading-tight line-clamp-2">
              {cat.name}
            </span>
          </Link>
        );
      })}
    </div>
  );
}
