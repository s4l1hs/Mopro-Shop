import { type HTMLAttributes } from "react";
import { cn } from "@/lib/utils";

interface StickyBarProps extends HTMLAttributes<HTMLDivElement> {
  position?: "bottom" | "top";
}

function StickyBar({ className, position = "bottom", children, ...props }: StickyBarProps) {
  return (
    <div
      className={cn(
        "sticky z-40 bg-background/95 backdrop-blur-sm border-border",
        position === "bottom"
          ? "bottom-0 border-t pb-safe"
          : "top-0 border-b",
        className,
      )}
      {...props}
    >
      {children}
    </div>
  );
}

export { StickyBar, type StickyBarProps };
