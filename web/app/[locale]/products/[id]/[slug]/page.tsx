import type { Metadata } from "next";
import { Suspense } from "react";
import { ProductDetailClient } from "@/components/pdp/product-detail-client";
import { Skeleton } from "@/components/ui/skeleton";

export const revalidate = 300;

interface Props {
  params: Promise<{ locale: string; id: string; slug: string }>;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { id, slug } = await params;
  const name = slug
    .split("-")
    .map((w) => (w[0]?.toUpperCase() ?? "") + w.slice(1))
    .join(" ");
  return {
    title: `${name} | Mopro`,
    description: `${name} — Mopro'da cashback avantajıyla satın al.`,
    openGraph: {
      title: `${name} | Mopro`,
      type: "website",
    },
    // Full OG image from product data is handled client-side
    alternates: {
      canonical: `/products/${id}/${slug}`,
    },
  };
}

function ProductSkeleton() {
  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-8">
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
          <Skeleton className="h-6 w-40 rounded" />
          <Skeleton className="h-10 w-56 rounded" />
          <Skeleton className="h-28 w-full rounded-lg" />
          <Skeleton className="h-11 w-full rounded" />
          <Skeleton className="h-11 w-full rounded" />
        </div>
      </div>
    </div>
  );
}

export default async function ProductPage({ params }: Props) {
  const { id, slug } = await params;
  const canonicalUrl = `/products/${id}/${slug}`;

  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6 md:py-8">
      <Suspense fallback={<ProductSkeleton />}>
        <ProductDetailClient productId={id} canonicalUrl={canonicalUrl} />
      </Suspense>
    </div>
  );
}
