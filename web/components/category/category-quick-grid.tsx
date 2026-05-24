import { cn } from "@/lib/utils";
import { CategoryCard, type CategoryCardProps } from "./category-card";

export interface CategoryQuickGridProps {
  categories: CategoryCardProps[];
  maxRows?: number;
  className?: string;
}

export function CategoryQuickGrid({
  categories,
  maxRows = 2,
  className,
}: CategoryQuickGridProps) {
  // Cols: 4 mobile, 6 sm, 8 md+. Limit visible cards to maxRows × cols.
  // We slice to the largest possible (maxRows × 8 = 16). CSS grid handles
  // the responsive column count, so visible rows depend on viewport.
  const maxVisible = maxRows * 8;
  const visible = categories.slice(0, maxVisible);

  return (
    <div
      className={cn(
        "grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 gap-2 sm:gap-3",
        className,
      )}
    >
      {visible.map((cat) => (
        <CategoryCard key={cat.slug} {...cat} />
      ))}
    </div>
  );
}
