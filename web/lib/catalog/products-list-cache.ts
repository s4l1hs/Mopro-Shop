import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { apiFetch } from "@/lib/api-client";
import type { Product } from "@/lib/types/product";

export const ITEMS_PER_PAGE = 24;

export interface FilterState {
  sort: string;
  page: number;
  minPrice: string;
  maxPrice: string;
  brands: string[];
  cashback: string; // "" | "10" | "15" | "20"
  freeShipping: boolean;
  inStock: boolean;
}

export const DEFAULT_FILTERS: FilterState = {
  sort: "recommended",
  page: 1,
  minPrice: "",
  maxPrice: "",
  brands: [],
  cashback: "",
  freeShipping: false,
  inStock: true,
};

export interface ProductFacets {
  brands: Array<{ name: string; count: number }>;
  priceRange: { min: number; max: number };
}

export interface ProductsListResponse {
  items: Product[];
  total: number;
  page: number;
  per_page: number;
  facets?: ProductFacets;
}

export function filtersFromSearchParams(
  params: { get: (key: string) => string | null },
): FilterState {
  const page = parseInt(params.get("page") ?? "1", 10);
  const brandParam = params.get("brand");
  return {
    sort: params.get("sort") ?? "recommended",
    page: isNaN(page) || page < 1 ? 1 : page,
    minPrice: params.get("minPrice") ?? "",
    maxPrice: params.get("maxPrice") ?? "",
    brands: brandParam ? brandParam.split(",").filter(Boolean) : [],
    cashback: params.get("cashback") ?? "",
    freeShipping: params.get("freeShipping") === "1",
    inStock: params.get("inStock") !== "0",
  };
}

export function filtersToURLParams(filters: FilterState): URLSearchParams {
  const p = new URLSearchParams();
  if (filters.sort !== "recommended") p.set("sort", filters.sort);
  if (filters.page > 1) p.set("page", String(filters.page));
  if (filters.minPrice) p.set("minPrice", filters.minPrice);
  if (filters.maxPrice) p.set("maxPrice", filters.maxPrice);
  if (filters.brands.length > 0) p.set("brand", filters.brands.join(","));
  if (filters.cashback) p.set("cashback", filters.cashback);
  if (filters.freeShipping) p.set("freeShipping", "1");
  if (!filters.inStock) p.set("inStock", "0");
  return p;
}

function buildApiUrl(base: string, filters: FilterState): string {
  const p = new URLSearchParams();
  p.set("sort", filters.sort);
  p.set("page", String(filters.page));
  p.set("limit", String(ITEMS_PER_PAGE));
  if (filters.minPrice) p.set("min_price", filters.minPrice);
  if (filters.maxPrice) p.set("max_price", filters.maxPrice);
  if (filters.brands.length > 0) p.set("brand", filters.brands.join(","));
  if (filters.cashback) p.set("cashback_min", filters.cashback);
  if (filters.freeShipping) p.set("free_shipping", "1");
  if (filters.inStock) p.set("in_stock", "1");
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}${p.toString()}`;
}

export function useProductsListQuery(base: string, filters: FilterState) {
  const url = buildApiUrl(base, filters);
  return useQuery({
    queryKey: ["products-list", url],
    queryFn: () => apiFetch<ProductsListResponse>(url),
    staleTime: 2 * 60 * 1000,
    placeholderData: keepPreviousData,
    retry: 1,
  });
}
