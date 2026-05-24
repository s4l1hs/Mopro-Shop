"use client";

import { ShoppingCart } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { CartLineItem } from "@/components/cart/cart-line-item";
import { formatPrice } from "@/lib/money";
import { useCartItems, useCartStore, useCartTotals } from "@/store/cart";

export default function CartPage() {
  const items = useCartItems();
  const { subtotalMinor } = useCartTotals();
  const removeItem = useCartStore((s) => s.removeItem);
  const updateQuantity = useCartStore((s) => s.updateQuantity);
  const clearCart = useCartStore((s) => s.clearCart);

  return (
    <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6 md:py-8">
      <h1 className="text-2xl font-bold tracking-tight mb-6">Sepetim</h1>

      {items.length === 0 ? (
        <div className="flex flex-col items-center justify-center gap-4 py-24 text-center">
          <ShoppingCart className="h-16 w-16 text-muted-foreground/20" />
          <div>
            <p className="text-lg font-medium text-foreground">Sepetiniz boş</p>
            <p className="text-muted-foreground mt-1">
              Alışverişe başlamak için ürün ekleyin.
            </p>
          </div>
          <Button asChild>
            <Link href="/categories">Ürünleri keşfet</Link>
          </Button>
        </div>
      ) : (
        <div className="grid lg:grid-cols-[1fr_360px] gap-6 lg:gap-10 items-start">
          {/* Left: items */}
          <div className="rounded-lg border border-border overflow-hidden">
            <div className="flex items-center justify-between px-4 py-3 bg-muted/40 border-b border-border">
              <span className="text-sm font-medium text-muted-foreground">
                {items.length} ürün
              </span>
              <button
                type="button"
                onClick={clearCart}
                className="text-xs text-destructive hover:underline underline-offset-2"
              >
                Sepeti temizle
              </button>
            </div>
            <div className="px-4 divide-y divide-border">
              {items.map((item) => (
                <CartLineItem
                  key={item.productId}
                  item={item}
                  onRemove={removeItem}
                  onUpdateQty={updateQuantity}
                />
              ))}
            </div>
          </div>

          {/* Right: summary + CTA */}
          <div className="rounded-lg border border-border p-4 space-y-4 lg:sticky lg:top-20">
            <h2 className="font-semibold text-foreground">Sipariş Özeti</h2>
            <Separator />
            <div className="space-y-2 text-sm">
              <div className="flex justify-between text-muted-foreground">
                <span>Ara toplam</span>
                <span>{formatPrice(subtotalMinor)}</span>
              </div>
              <div className="flex justify-between text-muted-foreground">
                <span>Kargo</span>
                <span>Ücretsiz</span>
              </div>
              <Separator />
              <div className="flex justify-between font-semibold text-base text-foreground">
                <span>Toplam</span>
                <span>{formatPrice(subtotalMinor)}</span>
              </div>
            </div>
            <Button className="w-full" size="lg" asChild>
              <Link href="/checkout">Ödemeye geç</Link>
            </Button>
            <Button variant="outline" className="w-full" asChild>
              <Link href="/categories">Alışverişe devam et</Link>
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
