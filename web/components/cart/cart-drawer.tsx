"use client";

import { ShoppingCart } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Separator } from "@/components/ui/separator";
import { formatPrice } from "@/lib/money";
import { useCartItems, useCartStore, useCartTotals } from "@/store/cart";
import { CartLineItem } from "./cart-line-item";

interface CartDrawerProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CartDrawer({ open, onOpenChange }: CartDrawerProps) {
  const items = useCartItems();
  const { subtotalMinor } = useCartTotals();
  const removeItem = useCartStore((s) => s.removeItem);
  const updateQuantity = useCartStore((s) => s.updateQuantity);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        className="flex flex-col p-0 w-full sm:max-w-[420px]"
      >
        <SheetHeader className="px-4 pt-4 pb-3 border-b border-border">
          <SheetTitle className="flex items-center gap-2">
            <ShoppingCart className="h-5 w-5" />
            Sepetim
            {items.length > 0 && (
              <span className="text-muted-foreground font-normal text-sm">
                ({items.length} ürün)
              </span>
            )}
          </SheetTitle>
        </SheetHeader>

        {/* Scrollable items */}
        <div className="flex-1 overflow-y-auto px-4">
          {items.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full gap-4 py-16 text-center">
              <ShoppingCart className="h-14 w-14 text-muted-foreground/20" />
              <div>
                <p className="font-medium text-foreground">Sepetiniz boş</p>
                <p className="text-sm text-muted-foreground mt-1">
                  Alışverişe başlamak için ürün ekleyin.
                </p>
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={() => onOpenChange(false)}
                asChild
              >
                <Link href="/categories">Ürünleri keşfet</Link>
              </Button>
            </div>
          ) : (
            <div className="divide-y divide-border">
              {items.map((item) => (
                <CartLineItem
                  key={item.productId}
                  item={item}
                  onRemove={removeItem}
                  onUpdateQty={updateQuantity}
                />
              ))}
            </div>
          )}
        </div>

        {/* Footer */}
        {items.length > 0 && (
          <div className="border-t border-border px-4 py-4 space-y-3">
            <div className="flex justify-between text-sm text-muted-foreground">
              <span>Ara toplam</span>
              <span>{formatPrice(subtotalMinor)}</span>
            </div>
            <Separator />
            <div className="flex justify-between font-semibold text-foreground">
              <span>Toplam</span>
              <span>{formatPrice(subtotalMinor)}</span>
            </div>
            <div className="flex flex-col gap-2 pt-1">
              <Button
                className="w-full"
                onClick={() => onOpenChange(false)}
                asChild
              >
                <Link href="/checkout">Ödemeye geç</Link>
              </Button>
              <Button
                variant="outline"
                className="w-full"
                onClick={() => onOpenChange(false)}
                asChild
              >
                <Link href="/cart">Sepeti görüntüle</Link>
              </Button>
            </div>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}
