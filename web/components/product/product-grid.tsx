import { type ReactNode } from "react";
import { cn } from "@/lib/utils";

interface ProductGridProps {
  children: ReactNode;
  className?: string;
}

export function ProductGrid({ children, className }: ProductGridProps) {
  return (
    <div
      className={cn(
        "grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3 sm:gap-4",
        className,
      )}
    >
      {children}
    </div>
  );
}
