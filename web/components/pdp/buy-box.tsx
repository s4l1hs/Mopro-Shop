"use client";

import { Coins, Minus, Package, Plus, ShieldCheck, RotateCcw, Truck } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { StarRating } from "@/components/ui/star-rating";
import { cashbackMonthlyMinor, formatPrice } from "@/lib/money";
import type { ProductDetail } from "@/lib/types/product";
import { MobileBuyBar } from "./mobile-buy-bar";

const TRUST_ITEMS = [
  { icon: Truck, label: "Aynı gün kargo" },
  { icon: ShieldCheck, label: "Güvenli ödeme" },
  { icon: RotateCcw, label: "14 gün iade" },
] as const;

interface BuyBoxProps {
  product: ProductDetail;
}

export function BuyBox({ product }: BuyBoxProps) {
  const [quantity, setQuantity] = useState(1);

  const maxQty = Math.min(10, product.stock ?? 10);
  const isOutOfStock = (product.stock ?? 1) === 0;

  const displayPriceMinor = product.discount_price_minor ?? product.price_minor;
  const hasDiscount = product.discount_price_minor !== undefined;
  const discountPct = hasDiscount
    ? Math.round((1 - displayPriceMinor / product.price_minor) * 100)
    : 0;

  const monthlyMinor = product.commission_pct_bps
    ? cashbackMonthlyMinor(displayPriceMinor, product.commission_pct_bps)
    : 0;
  // Preview: first 12 months total (plan is perpetual — TODO: update copy)
  const previewTotalMinor = monthlyMinor * 12;

  const handleAddToCart = () => {
    // TODO(U6): wire real addToCart API
    toast.success(`${product.title} sepete eklendi`);
  };

  return (
    <>
      <div className="space-y-4">
        {/* Brand */}
        {product.brand && (
          <Link
            href="#"
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            {product.brand}
          </Link>
        )}

        {/* Title */}
        <h1 className="text-xl md:text-2xl font-semibold text-foreground leading-snug">
          {product.title}
        </h1>

        {/* Rating */}
        {product.rating && (
          <div className="flex items-center gap-2">
            <StarRating value={product.rating.stars} size="sm" />
            <a
              href="#reviews"
              className="text-xs text-primary hover:underline underline-offset-2"
            >
              ({product.rating.count.toLocaleString("tr-TR")} değerlendirme)
            </a>
          </div>
        )}

        {/* Price */}
        <div className="flex items-end gap-3 flex-wrap">
          <span className="text-3xl font-bold text-primary leading-none">
            {formatPrice(displayPriceMinor, product.currency ?? "TRY")}
          </span>
          {hasDiscount && (
            <>
              <span className="text-base text-muted-foreground line-through leading-none">
                {formatPrice(product.price_minor, product.currency ?? "TRY")}
              </span>
              <Badge className="bg-destructive text-destructive-foreground">
                -%{discountPct}
              </Badge>
            </>
          )}
        </div>

        {/* Cashback card */}
        {monthlyMinor > 0 && (
          <div className="border-2 border-primary/30 bg-primary/5 rounded-lg p-4 space-y-1">
            <div className="flex items-center gap-1.5 text-primary text-xs font-semibold">
              <Coins className="h-4 w-4" />
              Aylık Cashback
            </div>
            <p className="text-2xl font-bold text-primary">
              {formatPrice(monthlyMinor, "TRY_COIN")}
              <span className="text-sm font-normal text-muted-foreground ml-1">/ ay</span>
            </p>
            <p className="text-xs text-muted-foreground">
              {/* TODO: final copy — plan is perpetual, 12 months shown as preview */}
              12 ay boyunca toplam{" "}
              <span className="font-medium text-foreground">
                {formatPrice(previewTotalMinor, "TRY_COIN")}
              </span>{" "}
              kazanırsın
            </p>
            <Dialog>
              <DialogTrigger asChild>
                <button
                  type="button"
                  className="text-xs text-primary hover:underline underline-offset-2"
                >
                  Nasıl çalışır? →
                </button>
              </DialogTrigger>
              <DialogContent className="max-w-sm">
                <DialogHeader>
                  <DialogTitle>Mopro Cashback Nasıl Çalışır?</DialogTitle>
                </DialogHeader>
                <div className="space-y-3 text-sm text-muted-foreground">
                  {/* TODO: final copy */}
                  <p>
                    Mopro&apos;da her aldığın üründen aylık cashback kazanırsın. Ürünü teslim
                    aldıktan 3 iş günü sonra planın aktif olur ve her ay Mopro Coin hesabına
                    aktarılır.
                  </p>
                  <p>
                    Komisyon tutarının yıllık faiz getirisi (%50 referans oran) aylık eşit
                    taksitlerle sana ödenir. Bu oran satın aldığın andaki değerde dondurulur.
                  </p>
                  <p>
                    Plan iptal edilene kadar her ay ödeme almaya devam edersin — süresiz.
                    1 Mopro Coin ≈ 1 TL değerindedir.
                  </p>
                </div>
              </DialogContent>
            </Dialog>
          </div>
        )}

        {/* Stock */}
        <div className="flex items-center gap-2">
          {isOutOfStock ? (
            <>
              <span className="h-2 w-2 rounded-full bg-destructive" />
              <span className="text-sm text-destructive">Tükendi</span>
            </>
          ) : (product.stock ?? 10) < 5 ? (
            <>
              <span className="h-2 w-2 rounded-full bg-warning" />
              <span className="text-sm text-warning">Son {product.stock} adet</span>
            </>
          ) : (
            <>
              <span className="h-2 w-2 rounded-full bg-success" />
              <span className="text-sm text-success">Stokta</span>
            </>
          )}
        </div>

        {/* Quantity */}
        {!isOutOfStock && (
          <div className="flex items-center gap-3">
            <span className="text-sm text-muted-foreground">Adet:</span>
            <div className="flex items-center border border-input rounded-md overflow-hidden">
              <button
                type="button"
                aria-label="Azalt"
                disabled={quantity <= 1}
                onClick={() => setQuantity((q) => Math.max(1, q - 1))}
                className="h-9 w-9 flex items-center justify-center hover:bg-accent disabled:opacity-40 transition-colors"
              >
                <Minus className="h-3.5 w-3.5" />
              </button>
              <span
                className="w-10 text-center text-sm font-medium select-none"
                aria-live="polite"
              >
                {quantity}
              </span>
              <button
                type="button"
                aria-label="Artır"
                disabled={quantity >= maxQty}
                onClick={() => setQuantity((q) => Math.min(maxQty, q + 1))}
                className="h-9 w-9 flex items-center justify-center hover:bg-accent disabled:opacity-40 transition-colors"
              >
                <Plus className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
        )}

        {/* CTAs */}
        <div className="space-y-2">
          <Button
            size="lg"
            className="w-full"
            disabled={isOutOfStock}
            onClick={handleAddToCart}
          >
            <Package className="h-4 w-4 mr-2" />
            {isOutOfStock ? "Stokta yok" : "Sepete ekle"}
          </Button>
          <Button
            size="lg"
            variant="outline"
            className="w-full"
            onClick={() => toast("Yakında kullanılabilir olacak.")}
          >
            Hemen al
          </Button>
        </div>

        {/* Trust strip */}
        <div className="flex items-center gap-4 pt-2 border-t border-border">
          {TRUST_ITEMS.map(({ icon: Icon, label }) => (
            <div key={label} className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Icon className="h-3.5 w-3.5 text-primary shrink-0" />
              {label}
            </div>
          ))}
        </div>
      </div>

      {/* Mobile buy bar — needs to be outside the scroll container */}
      <MobileBuyBar
        priceMinor={displayPriceMinor}
        {...(product.currency !== undefined && { currency: product.currency })}
        {...(product.commission_pct_bps !== undefined && {
          commissionPctBps: product.commission_pct_bps,
        })}
        isOutOfStock={isOutOfStock}
        onAddToCart={handleAddToCart}
      />
    </>
  );
}
