"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { ProductRail } from "@/components/product/product-rail";
import { useProductQuery, useRelatedProductsQuery } from "@/lib/catalog/products-cache";
import { BuyBox } from "./buy-box";
import { ImageGallery } from "./image-gallery";
import { ProductJsonLd } from "./product-jsonld";
import { ProductTabs } from "./product-tabs";

interface ProductDetailClientProps {
  productId: string;
  canonicalUrl: string;
}

function ProductSkeleton() {
  return (
    <div className="grid lg:grid-cols-[1fr_400px] gap-6 lg:gap-10">
      <div className="space-y-3">
        <Skeleton className="aspect-square w-full rounded-lg" />
        <div className="flex gap-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-16 w-16 rounded-md" />
          ))}
        </div>
      </div>
      <div className="space-y-4">
        <Skeleton className="h-4 w-24 rounded" />
        <Skeleton className="h-8 w-full rounded" />
        <Skeleton className="h-6 w-32 rounded" />
        <Skeleton className="h-10 w-48 rounded" />
        <Skeleton className="h-28 w-full rounded-lg" />
        <Skeleton className="h-10 w-full rounded" />
        <Skeleton className="h-10 w-full rounded" />
      </div>
    </div>
  );
}

function RelatedRail({ productId }: { productId: string }) {
  const { data, isLoading } = useRelatedProductsQuery(productId, 12);
  if (isLoading || !data?.items.length) return null;

  const products = data.items.map((p) => ({
    id: p.id,
    title: p.title,
    priceMinor: p.price_minor,
    coverImageUrl: p.cover_image_url,
    ...(p.slug !== undefined && { slug: p.slug }),
    ...(p.brand !== undefined && { brand: p.brand }),
    ...(p.commission_pct_bps !== undefined && { commissionBps: p.commission_pct_bps }),
    ...(p.currency !== undefined && { currency: p.currency }),
  }));

  return (
    <ProductRail title="Benzer ürünler" products={products} seeAllHref="/categories" />
  );
}

export function ProductDetailClient({ productId, canonicalUrl }: ProductDetailClientProps) {
  const { data: product, isLoading } = useProductQuery(productId);

  if (isLoading) return <ProductSkeleton />;

  if (!product) {
    return (
      <div className="py-16 text-center text-muted-foreground">Ürün bulunamadı.</div>
    );
  }

  const images =
    product.images && product.images.length > 0
      ? product.images
      : [product.cover_image_url];

  return (
    <>
      <ProductJsonLd product={product} canonicalUrl={canonicalUrl} />

      <div className="grid lg:grid-cols-[1fr_400px] gap-6 lg:gap-10">
        <ImageGallery images={images} title={product.title} />
        <BuyBox product={product} />
      </div>

      <div className="mt-10">
        <ProductTabs product={product} />
      </div>

      <div className="mt-12">
        <RelatedRail productId={productId} />
      </div>
    </>
  );
}
