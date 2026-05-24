"use client";

import { Minus, Plus, Trash2 } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { cashbackMonthlyMinor, formatPrice } from "@/lib/money";
import { cn } from "@/lib/utils";
import type { CartItem } from "@/store/cart";

interface CartLineItemProps {
  item: CartItem;
  onRemove: (productId: number) => void;
  onUpdateQty: (productId: number, quantity: number) => void;
  compact?: boolean;
}

export function CartLineItem({
  item,
  onRemove,
  onUpdateQty,
  compact = false,
}: CartLineItemProps) {
  const monthly = item.commissionPctBps
    ? cashbackMonthlyMinor(item.priceMinor, item.commissionPctBps) * item.quantity
    : 0;

  const productHref = item.slug
    ? `/products/${item.productId}/${item.slug}`
    : `/products/${item.productId}`;

  return (
    <div className={cn("flex gap-3", compact ? "py-2" : "py-3")}>
      {/* Image */}
      <Link href={productHref} className="shrink-0">
        <div
          className={cn(
            "relative rounded-md overflow-hidden bg-secondary",
            compact ? "h-14 w-14" : "h-20 w-20",
          )}
        >
          <Image
            src={item.coverImageUrl}
            alt={item.title}
            fill
            className="object-cover"
          />
        </div>
      </Link>

      {/* Details */}
      <div className="flex flex-1 flex-col min-w-0 gap-1">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            {item.brand && (
              <p className="text-xs text-muted-foreground truncate">{item.brand}</p>
            )}
            <Link href={productHref}>
              <p
                className={cn(
                  "font-medium text-foreground leading-snug line-clamp-2",
                  compact ? "text-xs" : "text-sm",
                )}
              >
                {item.title}
              </p>
            </Link>
          </div>
          <button
            type="button"
            aria-label="Ürünü sepetten kaldır"
            onClick={() => onRemove(item.productId)}
            className="shrink-0 text-muted-foreground hover:text-destructive transition-colors p-0.5"
          >
            <Trash2 className="h-3.5 w-3.5" />
          </button>
        </div>

        {monthly > 0 && (
          <p className="text-xs text-primary">
            +{formatPrice(monthly, "TRY_COIN")}/ay cashback
          </p>
        )}

        <div className="flex items-center justify-between mt-auto pt-1">
          {/* Quantity stepper */}
          <div className="flex items-center border border-input rounded overflow-hidden">
            <button
              type="button"
              aria-label="Azalt"
              disabled={item.quantity <= 1}
              onClick={() => onUpdateQty(item.productId, item.quantity - 1)}
              className="h-6 w-6 flex items-center justify-center hover:bg-accent disabled:opacity-40 transition-colors"
            >
              <Minus className="h-3 w-3" />
            </button>
            <span className="w-7 text-center text-xs font-medium select-none">
              {item.quantity}
            </span>
            <button
              type="button"
              aria-label="Artır"
              disabled={item.quantity >= 10}
              onClick={() => onUpdateQty(item.productId, item.quantity + 1)}
              className="h-6 w-6 flex items-center justify-center hover:bg-accent disabled:opacity-40 transition-colors"
            >
              <Plus className="h-3 w-3" />
            </button>
          </div>

          {/* Line total */}
          <p className={cn("font-semibold text-foreground", compact ? "text-sm" : "text-base")}>
            {formatPrice(item.priceMinor * item.quantity, item.currency)}
          </p>
        </div>
      </div>
    </div>
  );
}
