import { useQuery } from "@tanstack/react-query";
import { apiFetch } from "@/lib/api-client";
import type { ProductListResponse } from "@/lib/types/product";

export type ProductSort = "recommended" | "bestsellers" | "newest";

interface UseProductsQueryOptions {
  sort?: ProductSort;
  limit?: number;
}

export function useProductsQuery({ sort = "recommended", limit = 12 }: UseProductsQueryOptions = {}) {
  return useQuery({
    queryKey: ["products", sort, limit],
    queryFn: () =>
      apiFetch<ProductListResponse>(`/products?sort=${sort}&limit=${limit}`),
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}
