"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { cashbackMonthlyMinor, formatPrice } from "@/lib/money";
import { cn } from "@/lib/utils";

interface MobileBuyBarProps {
  priceMinor: number;
  currency?: string;
  commissionPctBps?: number;
  isOutOfStock: boolean;
  onAddToCart: () => void;
  className?: string;
}

export function MobileBuyBar({
  priceMinor,
  currency,
  commissionPctBps,
  isOutOfStock,
  onAddToCart,
  className,
}: MobileBuyBarProps) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const handleScroll = () => setVisible(window.scrollY > 400);
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  const monthly = commissionPctBps
    ? cashbackMonthlyMinor(priceMinor, commissionPctBps)
    : 0;

  return (
    <div
      className={cn(
        "fixed inset-x-0 z-40 lg:hidden bg-background border-t border-border transition-transform duration-200",
        // Position above the bottom tab bar (which is ~4rem / 64px)
        "bottom-[calc(4rem+env(safe-area-inset-bottom))]",
        visible ? "translate-y-0" : "translate-y-full",
        className,
      )}
    >
      <div className="flex items-center gap-3 px-4 py-3">
        <div className="flex-1 min-w-0">
          <p className="text-sm font-bold text-foreground leading-tight">
            {formatPrice(priceMinor, currency ?? "TRY")}
          </p>
          {monthly > 0 && (
            <p className="text-xs text-primary leading-tight">
              +{formatPrice(monthly, "TRY_COIN")}/ay cashback
            </p>
          )}
        </div>
        <Button
          className="shrink-0"
          disabled={isOutOfStock}
          onClick={onAddToCart}
        >
          {isOutOfStock ? "Stok yok" : "Sepete ekle"}
        </Button>
      </div>
    </div>
  );
}
