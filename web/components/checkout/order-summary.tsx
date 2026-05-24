"use client";

import { Coins } from "lucide-react";
import { Separator } from "@/components/ui/separator";
import { formatPrice } from "@/lib/money";
import { useCartItems, useCartTotals } from "@/store/cart";
import { CartLineItem } from "@/components/cart/cart-line-item";

interface OrderSummaryProps {
  compact?: boolean;
}

export function OrderSummary({ compact = false }: OrderSummaryProps) {
  const items = useCartItems();
  const { subtotalMinor, monthlyCashbackMinor } = useCartTotals();

  // TODO(U8): shipping fee from selected carrier
  const shippingMinor = 0;
  const totalMinor = subtotalMinor + shippingMinor;

  return (
    <div className="space-y-3">
      {/* Line items */}
      <div className="divide-y divide-border">
        {items.map((item) => (
          <CartLineItem
            key={item.productId}
            item={item}
            compact={compact}
            onRemove={() => {/* read-only in summary */}}
            onUpdateQty={() => {/* read-only in summary */}}
          />
        ))}
      </div>

      <Separator />

      {/* Totals */}
      <div className="space-y-1.5 text-sm">
        <div className="flex justify-between text-muted-foreground">
          <span>Ara toplam</span>
          <span>{formatPrice(subtotalMinor)}</span>
        </div>
        <div className="flex justify-between text-muted-foreground">
          <span>Kargo</span>
          <span>{shippingMinor === 0 ? "Ücretsiz" : formatPrice(shippingMinor)}</span>
        </div>
        <Separator />
        <div className="flex justify-between font-semibold text-base text-foreground">
          <span>Toplam</span>
          <span>{formatPrice(totalMinor)}</span>
        </div>
        {monthlyCashbackMinor > 0 && (
          <div className="flex items-center justify-between text-primary text-sm pt-1 border-t border-primary/20">
            <span className="flex items-center gap-1">
              <Coins className="h-3.5 w-3.5" />
              Aylık cashback kazancı
            </span>
            <span className="font-semibold">
              {formatPrice(monthlyCashbackMinor, "TRY_COIN")}/ay
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
