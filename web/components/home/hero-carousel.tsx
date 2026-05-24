"use client";

import Autoplay from "embla-carousel-autoplay";
import useEmblaCarousel from "embla-carousel-react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import type { HeroSlide } from "@/lib/home/hero-slides";
import { cn } from "@/lib/utils";

interface HeroCarouselProps {
  slides: HeroSlide[];
}

export function HeroCarousel({ slides }: HeroCarouselProps) {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [emblaRef, emblaApi] = useEmblaCarousel(
    { loop: true },
    [Autoplay({ delay: 5000, stopOnInteraction: false, stopOnMouseEnter: true })],
  );

  const onSelect = useCallback(() => {
    if (!emblaApi) return;
    setSelectedIndex(emblaApi.selectedScrollSnap());
  }, [emblaApi]);

  useEffect(() => {
    if (!emblaApi) return;
    onSelect();
    emblaApi.on("select", onSelect);
    return () => {
      emblaApi.off("select", onSelect);
    };
  }, [emblaApi, onSelect]);

  const scrollPrev = useCallback(() => emblaApi?.scrollPrev(), [emblaApi]);
  const scrollNext = useCallback(() => emblaApi?.scrollNext(), [emblaApi]);

  return (
    <div className="relative overflow-hidden rounded-xl">
      <div ref={emblaRef} className="overflow-hidden">
        <div className="flex">
          {slides.map((slide) => (
            <div key={slide.id} className="flex-shrink-0 w-full">
              <div
                className={cn(
                  "relative w-full aspect-[16/9] md:aspect-[21/9] flex items-center",
                  slide.bgClass,
                )}
              >
                {/* Dark overlay for text readability */}
                <div className="absolute inset-0 bg-black/25" />

                {/* Text content */}
                <div className="relative z-10 px-8 sm:px-12 md:px-16 max-w-xl">
                  <h2 className="text-xl sm:text-2xl md:text-3xl lg:text-4xl font-bold text-white leading-tight">
                    {slide.title}
                  </h2>
                  <p className="mt-2 sm:mt-3 text-sm sm:text-base text-white/85 leading-relaxed">
                    {slide.subtitle}
                  </p>
                  <Button
                    asChild
                    className="mt-4 sm:mt-5 bg-white text-primary hover:bg-white/90 font-semibold"
                  >
                    <Link href={slide.cta.href}>{slide.cta.label}</Link>
                  </Button>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Prev / Next — lg+ only */}
      <button
        type="button"
        onClick={scrollPrev}
        aria-label="Önceki slayt"
        className="hidden lg:flex absolute left-4 top-1/2 -translate-y-1/2 z-20 h-10 w-10 items-center justify-center rounded-full bg-white/20 text-white backdrop-blur-sm hover:bg-white/35 transition-colors"
      >
        <ChevronLeft className="h-5 w-5" />
      </button>
      <button
        type="button"
        onClick={scrollNext}
        aria-label="Sonraki slayt"
        className="hidden lg:flex absolute right-4 top-1/2 -translate-y-1/2 z-20 h-10 w-10 items-center justify-center rounded-full bg-white/20 text-white backdrop-blur-sm hover:bg-white/35 transition-colors"
      >
        <ChevronRight className="h-5 w-5" />
      </button>

      {/* Dot indicators */}
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-20 flex gap-1.5">
        {slides.map((slide, i) => (
          <button
            key={slide.id}
            type="button"
            onClick={() => emblaApi?.scrollTo(i)}
            aria-label={`Slayt ${i + 1}`}
            className={cn(
              "h-1.5 rounded-full transition-all duration-200",
              i === selectedIndex ? "w-6 bg-white" : "w-1.5 bg-white/50 hover:bg-white/75",
            )}
          />
        ))}
      </div>
    </div>
  );
}
