"use client";

import { useQueries } from "@tanstack/react-query";
import { Heart } from "lucide-react";
import Link from "next/link";
import { ProductCard } from "@/components/product/product-card";
import { ProductGrid } from "@/components/product/product-grid";
import { Skeleton } from "@/components/ui/skeleton";
import { apiFetch } from "@/lib/api-client";
import { useFavoritesStore } from "@/lib/favorites/favorites-store";
import type { ProductDetail } from "@/lib/types/product";

export default function FavoritesPage() {
  const ids = useFavoritesStore((s) => s.ids);

  const results = useQueries({
    queries: ids.map((id) => ({
      queryKey: ["product", id],
      queryFn: () => apiFetch<ProductDetail>(`/products/${id}`),
      staleTime: 5 * 60 * 1000,
      retry: 1,
    })),
  });

  const isLoading = results.some((r) => r.isLoading);
  const products = results.flatMap((r) => (r.data ? [r.data] : []));

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-foreground">Favorilerim</h1>
        {ids.length > 0 && (
          <p className="text-sm text-muted-foreground">{ids.length} ürün</p>
        )}
      </div>

      {ids.length === 0 ? (
        <div className="py-20 text-center space-y-4">
          <div className="flex justify-center">
            <div className="h-16 w-16 rounded-full bg-muted flex items-center justify-center">
              <Heart className="h-8 w-8 text-muted-foreground" />
            </div>
          </div>
          <p className="font-medium text-muted-foreground">Henüz favori eklemedin</p>
          <p className="text-sm text-muted-foreground max-w-xs mx-auto">
            Ürünlerin üzerindeki ❤ ikonuna dokun, beğendiklerini burada hızlıca bul.
          </p>
          <Link
            href="/products"
            className="inline-block mt-2 text-sm text-primary hover:underline underline-offset-4"
          >
            Ürünleri keşfet
          </Link>
        </div>
      ) : isLoading ? (
        <ProductGrid>
          {ids.map((id) => (
            <Skeleton key={id} className="aspect-[3/4] rounded-lg" />
          ))}
        </ProductGrid>
      ) : (
        <ProductGrid>
          {products.map((p) => (
            <ProductCard
              key={p.id}
              id={p.id}
              {...(p.slug !== undefined && { slug: p.slug })}
              title={p.title}
              {...(p.brand !== undefined && { brand: p.brand })}
              priceMinor={p.price_minor}
              coverImageUrl={p.cover_image_url}
              {...(p.commission_pct_bps !== undefined && { commissionBps: p.commission_pct_bps })}
              {...(p.currency !== undefined && { currency: p.currency })}
            />
          ))}
        </ProductGrid>
      )}
    </div>
  );
}
