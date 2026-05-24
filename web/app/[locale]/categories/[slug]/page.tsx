import type { Metadata } from "next";
import { Suspense } from "react";
import { CategoryHeader } from "@/components/catalog/category-header";
import { CatalogShell } from "@/components/catalog/catalog-shell";
import { Skeleton } from "@/components/ui/skeleton";

interface Props {
  params: Promise<{ locale: string; slug: string }>;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const name = slug
    .split("-")
    .map((w) => (w[0]?.toUpperCase() ?? "") + w.slice(1))
    .join(" ");
  return {
    title: `${name} | Mopro`,
    description: `Mopro'da ${name} kategorisindeki ürünleri cashback avantajıyla keşfet.`,
  };
}

function CatalogSkeleton() {
  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6">
      <div className="space-y-3 mb-6">
        <Skeleton className="h-4 w-48 rounded" />
        <Skeleton className="h-8 w-56 rounded" />
      </div>
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3 md:gap-4">
        {Array.from({ length: 12 }).map((_, i) => (
          <div key={i} className="space-y-2">
            <Skeleton className="aspect-square w-full rounded-xl" />
            <Skeleton className="h-3 w-24 rounded" />
            <Skeleton className="h-4 w-full rounded" />
          </div>
        ))}
      </div>
    </div>
  );
}

export default async function CategoryPage({ params }: Props) {
  const { slug } = await params;
  return (
    <Suspense fallback={<CatalogSkeleton />}>
      <CatalogShell
        headerContent={<CategoryHeader slug={slug} />}
        queryBase={`/products?category=${encodeURIComponent(slug)}`}
      />
    </Suspense>
  );
}
