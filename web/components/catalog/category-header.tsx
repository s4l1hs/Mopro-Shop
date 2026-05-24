"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { useCategories, useCategoryBySlugQuery } from "@/lib/catalog/categories-cache";
import { Breadcrumb } from "./breadcrumb";

interface CategoryHeaderProps {
  slug: string;
}

export function CategoryHeader({ slug }: CategoryHeaderProps) {
  const { data: categories, isLoading: catsLoading } = useCategories();
  const { data: category, isLoading: catLoading } = useCategoryBySlugQuery(slug);

  const isLoading = catsLoading || catLoading;

  const parent =
    category?.parent_id != null
      ? categories?.find((c) => c.id === category.parent_id)
      : null;

  const displayName =
    category?.name ??
    slug
      .split("-")
      .map((w) => (w[0]?.toUpperCase() ?? "") + w.slice(1))
      .join(" ");

  const breadcrumbItems = [
    { label: "Ana Sayfa", href: "/" },
    ...(parent ? [{ label: parent.name, href: `/categories/${parent.slug}` }] : []),
    { label: displayName },
  ];

  if (isLoading) {
    return (
      <div className="space-y-2">
        <Skeleton className="h-4 w-48 rounded" />
        <Skeleton className="h-8 w-64 rounded" />
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <Breadcrumb items={breadcrumbItems} />
      <h1 className="text-2xl font-bold text-foreground">{displayName}</h1>
    </div>
  );
}
