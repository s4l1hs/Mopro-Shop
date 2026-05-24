"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { ProductRail } from "@/components/product/product-rail";
import type { ProductCardProps } from "@/components/product/product-card";
import { useProductsQuery } from "@/lib/catalog/products-cache";
import type { Product } from "@/lib/types/product";
import type { ProductSort } from "@/lib/catalog/products-cache";

function toCardProps(item: Product): ProductCardProps {
  return {
    id: item.id,
    title: item.title,
    priceMinor: item.price_minor,
    coverImageUrl: item.cover_image_url,
    ...(item.slug !== undefined && { slug: item.slug }),
    ...(item.brand !== undefined && { brand: item.brand }),
    ...(item.commission_pct_bps !== undefined && { commissionBps: item.commission_pct_bps }),
    ...(item.currency !== undefined && { currency: item.currency }),
  };
}

interface HomeProductRailProps {
  title: string;
  sort: ProductSort;
  seeAllHref?: string;
  className?: string;
}

export function HomeProductRail({ title, sort, seeAllHref, className }: HomeProductRailProps) {
  const { data, isLoading } = useProductsQuery({ sort, limit: 12 });

  if (isLoading) {
    return (
      <section className="space-y-3">
        <Skeleton className="h-6 w-48 rounded" />
        <div className="flex gap-3 overflow-hidden">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="w-[180px] flex-shrink-0 space-y-2">
              <Skeleton className="aspect-square w-full rounded-xl" />
              <Skeleton className="h-3 w-24 rounded" />
              <Skeleton className="h-4 w-32 rounded" />
            </div>
          ))}
        </div>
      </section>
    );
  }

  const products = (data?.items ?? []).map(toCardProps);
  if (products.length === 0) return null;

  return (
    <ProductRail
      title={title}
      products={products}
      {...(seeAllHref !== undefined && { seeAllHref })}
      {...(className !== undefined && { className })}
    />
  );
}
