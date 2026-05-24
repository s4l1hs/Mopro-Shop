"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { type ReactNode, useCallback } from "react";
import { FilterDrawer } from "./filter-drawer";
import { FilterSidebar } from "./filter-sidebar";
import { Pagination } from "./pagination";
import { ProductGrid } from "./product-grid";
import { SortSelect } from "./sort-select";
import {
  DEFAULT_FILTERS,
  ITEMS_PER_PAGE,
  filtersFromSearchParams,
  filtersToURLParams,
  useProductsListQuery,
} from "@/lib/catalog/products-list-cache";
import type { FilterState } from "@/lib/catalog/products-list-cache";

const FILTER_KEYS = [
  "sort", "page", "minPrice", "maxPrice", "brand", "cashback", "freeShipping", "inStock",
] as const;

interface CatalogShellProps {
  headerContent: ReactNode;
  /** API base path, e.g. "/products?category=elektronik" or "/products?q=ayakkabı" */
  queryBase: string;
  /** Custom empty state rendered when total === 0 and not loading */
  emptyContent?: ReactNode;
}

export function CatalogShell({ headerContent, queryBase, emptyContent }: CatalogShellProps) {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  const filters = filtersFromSearchParams(searchParams);
  const { data, isLoading } = useProductsListQuery(queryBase, filters);

  /** Merge filter updates into URL while preserving non-filter params (e.g. ?q=) */
  const applyFilters = useCallback(
    (update: Partial<FilterState>) => {
      const next = { ...filters, ...update };
      const preserved = new URLSearchParams(searchParams.toString());
      FILTER_KEYS.forEach((k) => preserved.delete(k));
      filtersToURLParams(next).forEach((v, k) => preserved.set(k, v));
      const qs = preserved.toString();
      router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
    },
    [filters, router, pathname, searchParams],
  );

  /** Clear filter keys, preserving non-filter params */
  const clearFilters = useCallback(() => {
    const preserved = new URLSearchParams(searchParams.toString());
    FILTER_KEYS.forEach((k) => preserved.delete(k));
    const qs = preserved.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
  }, [router, pathname, searchParams]);

  const total = data?.total ?? 0;
  const totalPages = Math.ceil(total / ITEMS_PER_PAGE);

  const handlePageChange = (page: number) => {
    applyFilters({ page });
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6">
      {/* Breadcrumb / H1 slot */}
      <div className="mb-5">{headerContent}</div>

      <div className="lg:grid lg:grid-cols-[260px_1fr] lg:gap-6">
        {/* Desktop filter sidebar */}
        <div className="hidden lg:block">
          <div className="sticky top-32 max-h-[calc(100vh-9rem)] overflow-y-auto">
            <FilterSidebar
              filters={filters}
              {...(data?.facets !== undefined && { facets: data.facets })}
              onChange={applyFilters}
              onClear={clearFilters}
            />
          </div>
        </div>

        {/* Product area */}
        <div className="min-w-0">
          {/* Toolbar */}
          <div className="flex items-center justify-between gap-3 mb-4 flex-wrap">
            <p className="text-sm text-muted-foreground">
              {isLoading ? "Yükleniyor…" : `${total.toLocaleString("tr-TR")} ürün`}
            </p>
            <div className="flex items-center gap-2">
              <FilterDrawer
                filters={filters}
                {...(data?.facets !== undefined && { facets: data.facets })}
                resultCount={total}
                onChange={applyFilters}
                onClear={clearFilters}
              />
              <SortSelect
                value={filters.sort}
                onChange={(sort) => applyFilters({ sort, page: 1 })}
              />
            </div>
          </div>

          {/* Grid */}
          <ProductGrid
            products={data?.items ?? []}
            isLoading={isLoading}
            onClearFilters={clearFilters}
            {...(emptyContent !== undefined && { emptyContent })}
          />

          {/* Pagination */}
          {totalPages > 1 && !isLoading && (
            <Pagination
              currentPage={filters.page}
              totalPages={totalPages}
              onPageChange={handlePageChange}
              className="mt-8"
            />
          )}
        </div>
      </div>
    </div>
  );
}

/** Thin wrapper for Suspense boundaries — re-export the default filters sentinel */
export { DEFAULT_FILTERS };
