"use client";

import { motion } from "framer-motion";
import { Heart } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { CashbackChip } from "./cashback-chip";
import { PriceDisplay } from "./price-display";

export interface ProductCardProps {
  id: number | string;
  slug?: string;
  title: string;
  brand?: string;
  priceMinor: number;
  coverImageUrl: string;
  commissionBps?: number;
  currency?: string;
  className?: string;
  rating?: { stars: number; count: number };
}

export function ProductCard({
  id,
  slug,
  title,
  brand,
  priceMinor,
  coverImageUrl,
  commissionBps,
  currency = "TRY",
  className,
}: ProductCardProps) {
  const href = slug ? `/products/${id}/${slug}` : `/products/${id}`;

  return (
    <Link
      href={href}
      className={cn(
        "group block rounded-lg border border-border bg-card text-card-foreground",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
        "active:scale-[0.98] transition-transform",
        className,
      )}
    >
      <motion.div
        whileHover={{ scale: 1.02 }}
        transition={{ duration: 0.18, ease: "easeOut" }}
        className="rounded-lg overflow-hidden shadow-sm group-hover:shadow-lg group-hover:border-primary/40 transition-shadow"
      >
        {/* Image */}
        <div className="relative aspect-square overflow-hidden bg-muted">
          <Image
            src={coverImageUrl}
            alt={title}
            fill
            sizes="(max-width: 640px) 50vw, (max-width: 768px) 33vw, (max-width: 1024px) 25vw, 20vw"
            className="object-cover transition-transform duration-300 group-hover:scale-105"
            loading="lazy"
          />
          {/* Heart button */}
          <button
            type="button"
            aria-label="Favorilere ekle"
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              toast("Yakında — favorilere ekle özelliği");
            }}
            className={cn(
              "absolute top-2 right-2 flex items-center justify-center p-1.5 rounded-full",
              "bg-background/80 backdrop-blur-sm text-foreground/70 hover:text-foreground",
              "transition-colors",
            )}
          >
            <Heart className="h-4 w-4" />
          </button>
        </div>

        {/* Body */}
        <div className="p-3 space-y-1">
          {brand && (
            <p className="text-xs text-muted-foreground line-clamp-1">{brand}</p>
          )}
          <p className="text-sm text-foreground line-clamp-2 min-h-[2.5rem] leading-tight">
            {title}
          </p>
          {commissionBps != null && commissionBps > 0 && (
            <CashbackChip priceMinor={priceMinor} commissionBps={commissionBps} size="sm" />
          )}
          <PriceDisplay minor={priceMinor} currency={currency} size="lg" />
        </div>
      </motion.div>
    </Link>
  );
}
