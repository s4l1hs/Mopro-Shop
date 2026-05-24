import { Star } from "lucide-react";
import { cn } from "@/lib/utils";

interface StarRatingProps {
  value: number;
  max?: number;
  size?: "sm" | "md";
  className?: string;
}

export function StarRating({ value, max = 5, size = "md", className }: StarRatingProps) {
  const cls = size === "sm" ? "h-3 w-3" : "h-4 w-4";
  return (
    <div
      className={cn("flex items-center", className)}
      aria-label={`${value} / ${max} yıldız`}
      role="img"
    >
      {Array.from({ length: max }).map((_, i) => {
        const fill = Math.min(1, Math.max(0, value - i));
        return (
          <span key={i} className="relative inline-block">
            <Star className={cn(cls, "text-muted-foreground/30")} />
            {fill > 0 && (
              <span
                className="absolute inset-0 overflow-hidden"
                style={{ width: `${fill * 100}%` }}
              >
                <Star className={cn(cls, "text-warning fill-warning")} />
              </span>
            )}
          </span>
        );
      })}
    </div>
  );
}
