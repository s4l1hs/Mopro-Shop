import { formatPrice } from "@/lib/money";
import { cn } from "@/lib/utils";

export interface PriceDisplayProps {
  minor: number;
  currency?: string;
  size?: "sm" | "md" | "lg" | "xl";
  discounted?: { fromMinor: number };
  className?: string;
}

const sizeClasses = {
  sm: "text-sm font-semibold",
  md: "text-base font-semibold",
  lg: "text-lg font-bold",
  xl: "text-2xl font-bold",
} as const;

export function PriceDisplay({
  minor,
  currency = "TRY",
  size = "md",
  discounted,
  className,
}: PriceDisplayProps) {
  return (
    <div className={cn("flex items-baseline gap-2", className)}>
      <span className={cn("text-primary", sizeClasses[size])}>
        {formatPrice(minor, currency)}
      </span>
      {discounted && (
        <span className="text-sm text-muted-foreground line-through">
          {formatPrice(discounted.fromMinor, currency)}
        </span>
      )}
    </div>
  );
}
