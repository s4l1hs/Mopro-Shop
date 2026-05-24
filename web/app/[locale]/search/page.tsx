import type { Metadata } from "next";
import { Suspense } from "react";
import { SearchShell } from "@/components/catalog/search-shell";
import { Skeleton } from "@/components/ui/skeleton";

interface Props {
  searchParams: Promise<{ q?: string }>;
}

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const { q } = await searchParams;
  const query = q?.trim() ?? "";
  return {
    title: query ? `"${query}" için sonuçlar | Mopro` : "Arama | Mopro",
    description: query
      ? `Mopro'da "${query}" için bulunan ürünleri keşfet.`
      : "Mopro'da ürün ara.",
  };
}

function SearchSkeleton() {
  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6">
      <Skeleton className="h-8 w-64 rounded mb-6" />
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

export default function SearchPage() {
  return (
    <Suspense fallback={<SearchSkeleton />}>
      <SearchShell />
    </Suspense>
  );
}
