"use client";

import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ProductCard } from "@/components/product/product-card";
import type { Product } from "@/lib/types/product";
import { cn } from "@/lib/utils";

interface ProductGridProps {
  products: Product[];
  isLoading: boolean;
  onClearFilters: () => void;
  emptyContent?: ReactNode;
  className?: string;
}

function toCardProps(p: Product) {
  return {
    id: p.id,
    title: p.title,
    priceMinor: p.price_minor,
    coverImageUrl: p.cover_image_url,
    ...(p.slug !== undefined && { slug: p.slug }),
    ...(p.brand !== undefined && { brand: p.brand }),
    ...(p.commission_pct_bps !== undefined && { commissionBps: p.commission_pct_bps }),
    ...(p.currency !== undefined && { currency: p.currency }),
  };
}

export function ProductGrid({
  products,
  isLoading,
  onClearFilters,
  emptyContent,
  className,
}: ProductGridProps) {
  const gridClass = "grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 md:gap-4";

  if (isLoading) {
    return (
      <div className={cn(gridClass, className)}>
        {Array.from({ length: 12 }).map((_, i) => (
          <div key={i} className="space-y-2">
            <Skeleton className="aspect-square w-full rounded-xl" />
            <Skeleton className="h-3 w-20 rounded" />
            <Skeleton className="h-4 w-32 rounded" />
            <Skeleton className="h-3 w-16 rounded" />
          </div>
        ))}
      </div>
    );
  }

  if (products.length === 0) {
    if (emptyContent) return <div className={className}>{emptyContent}</div>;
    return (
      <div className={cn("flex flex-col items-center justify-center py-16 gap-4", className)}>
        <p className="text-muted-foreground text-sm">Bu filtrelerle ürün bulunamadı.</p>
        <Button variant="outline" onClick={onClearFilters}>
          Filtreleri temizle
        </Button>
      </div>
    );
  }

  return (
    <div className={cn(gridClass, className)}>
      {products.map((p) => (
        <ProductCard key={p.id} {...toCardProps(p)} />
      ))}
    </div>
  );
}
