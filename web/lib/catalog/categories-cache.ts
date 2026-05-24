import { useQuery } from "@tanstack/react-query";
import { apiFetch } from "@/lib/api-client";

export interface Category {
  id: number;
  slug: string;
  name: string;
  parent_id: number | null;
}

async function fetchCategories(): Promise<Category[]> {
  return apiFetch<Category[]>("/categories");
}

export function useCategories() {
  return useQuery({
    queryKey: ["categories"],
    queryFn: fetchCategories,
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}

export function buildCategoryTree(
  categories: Category[],
): { parent: Category; children: Category[] }[] {
  const roots = categories.filter((c) => c.parent_id === null);
  return roots.map((parent) => ({
    parent,
    children: categories.filter((c) => c.parent_id === parent.id).slice(0, 4),
  }));
}

export function useCategoryBySlugQuery(slug: string) {
  return useQuery({
    queryKey: ["category", slug],
    queryFn: async () => {
      const cats = await fetchCategories();
      return cats.find((c) => c.slug === slug) ?? null;
    },
    staleTime: 5 * 60 * 1000,
    retry: 1,
  });
}
