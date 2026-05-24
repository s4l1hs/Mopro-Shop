import { useQuery } from "@tanstack/react-query";
import { apiFetch } from "@/lib/api-client";
import type { ProductDetail } from "@/lib/types/product";
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

export function useProductQuery(id: number | string) {
  return useQuery({
    queryKey: ["product", String(id)],
    queryFn: () => apiFetch<ProductDetail>(`/products/${id}`),
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}

export function useRelatedProductsQuery(productId: number | string, limit = 12) {
  return useQuery({
    queryKey: ["products-related", String(productId), limit],
    queryFn: () =>
      apiFetch<ProductListResponse>(`/products?relatedTo=${productId}&limit=${limit}`),
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}
