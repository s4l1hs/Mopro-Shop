"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import { ProductCard, type ProductCardProps } from "./product-card";

export interface ProductRailProps {
  title: string;
  products: ProductCardProps[];
  seeAllHref?: string;
  className?: string;
}

export function ProductRail({ title, products, seeAllHref, className }: ProductRailProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [canScrollLeft, setCanScrollLeft] = useState(false);
  const [canScrollRight, setCanScrollRight] = useState(true);

  const updateScrollState = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    setCanScrollLeft(el.scrollLeft > 4);
    setCanScrollRight(el.scrollLeft < el.scrollWidth - el.clientWidth - 4);
  }, []);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    updateScrollState();
    el.addEventListener("scroll", updateScrollState, { passive: true });
    return () => el.removeEventListener("scroll", updateScrollState);
  }, [updateScrollState]);

  const scrollBy = (direction: "left" | "right") => {
    const el = scrollRef.current;
    if (!el) return;
    const cardWidth = el.firstElementChild?.clientWidth ?? 200;
    el.scrollBy({ left: direction === "right" ? cardWidth * 2 : -(cardWidth * 2), behavior: "smooth" });
  };

  return (
    <section className={cn("space-y-3", className)}>
      {/* Header */}
      <div className="flex items-center justify-between px-0">
        <h2 className="text-base font-semibold text-foreground sm:text-lg">{title}</h2>
        {seeAllHref && (
          <Link
            href={seeAllHref}
            className="text-sm text-primary hover:underline underline-offset-4 shrink-0"
          >
            Tümünü Gör →
          </Link>
        )}
      </div>

      {/* Scroll area with arrows */}
      <div className="relative group/rail">
        {/* Left arrow */}
        <button
          type="button"
          aria-label="Sola kaydır"
          onClick={() => scrollBy("left")}
          className={cn(
            "hidden md:flex absolute left-0 top-1/2 -translate-y-1/2 -translate-x-3 z-10",
            "h-8 w-8 items-center justify-center rounded-full border bg-background shadow-md",
            "text-foreground hover:bg-accent transition-all",
            !canScrollLeft && "opacity-0 pointer-events-none",
          )}
        >
          <ChevronLeft className="h-4 w-4" />
        </button>

        {/* Cards */}
        <div
          ref={scrollRef}
          className={cn(
            "flex overflow-x-auto gap-3 pb-2 snap-x snap-mandatory scroll-smooth",
            "[&::-webkit-scrollbar]:hidden [scrollbar-width:none]",
          )}
        >
          {products.map((product) => (
            <ProductCard
              key={product.id}
              {...product}
              className="w-[180px] sm:w-[200px] md:w-[220px] flex-shrink-0 snap-start"
            />
          ))}
        </div>

        {/* Right arrow */}
        <button
          type="button"
          aria-label="Sağa kaydır"
          onClick={() => scrollBy("right")}
          className={cn(
            "hidden md:flex absolute right-0 top-1/2 -translate-y-1/2 translate-x-3 z-10",
            "h-8 w-8 items-center justify-center rounded-full border bg-background shadow-md",
            "text-foreground hover:bg-accent transition-all",
            !canScrollRight && "opacity-0 pointer-events-none",
          )}
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
    </section>
  );
}
