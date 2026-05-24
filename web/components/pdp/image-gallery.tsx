"use client";

import useEmblaCarousel from "embla-carousel-react";
import { ChevronLeft, ChevronRight, ZoomIn } from "lucide-react";
import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  Dialog,
  DialogContent,
} from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

interface ImageGalleryProps {
  images: string[];
  title: string;
}

export function ImageGallery({ images, title }: ImageGalleryProps) {
  const allImages = images.length > 0 ? images : ["/placeholder-product.png"];
  const [activeIndex, setActiveIndex] = useState(0);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [dialogIndex, setDialogIndex] = useState(0);
  const [zoomOrigin, setZoomOrigin] = useState("50% 50%");
  const [isZoomed, setIsZoomed] = useState(false);
  const thumbsRef = useRef<HTMLDivElement | undefined>(undefined);

  // Mobile Embla
  const [emblaRef, emblaApi] = useEmblaCarousel({ loop: false }, []);
  const [mobileIndex, setMobileIndex] = useState(0);

  useEffect(() => {
    if (!emblaApi) return;
    const onSelect = () => setMobileIndex(emblaApi.selectedScrollSnap());
    emblaApi.on("select", onSelect);
    return () => { emblaApi.off("select", onSelect); };
  }, [emblaApi]);

  const currentImage = allImages[activeIndex] ?? allImages[0] ?? "";
  const dialogImage = allImages[dialogIndex] ?? allImages[0] ?? "";

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    const x = (((e.clientX - r.left) / r.width) * 100).toFixed(1);
    const y = (((e.clientY - r.top) / r.height) * 100).toFixed(1);
    setZoomOrigin(`${x}% ${y}%`);
  };

  const scrollThumbs = (dir: "left" | "right") => {
    const el = thumbsRef.current;
    if (!el) return;
    el.scrollBy({ left: dir === "right" ? 88 : -88, behavior: "smooth" });
  };

  const openDialog = (i: number) => {
    setDialogIndex(i);
    setDialogOpen(true);
  };

  const dialogPrev = useCallback(() => {
    setDialogIndex((i) => (i - 1 + allImages.length) % allImages.length);
  }, [allImages.length]);

  const dialogNext = useCallback(() => {
    setDialogIndex((i) => (i + 1) % allImages.length);
  }, [allImages.length]);

  return (
    <>
      {/* Desktop gallery */}
      <div className="hidden md:block space-y-3">
        {/* Main image */}
        <div
          className="relative aspect-square rounded-lg overflow-hidden bg-secondary cursor-zoom-in"
          onMouseEnter={() => setIsZoomed(true)}
          onMouseLeave={() => setIsZoomed(false)}
          onMouseMove={handleMouseMove}
          onClick={() => openDialog(activeIndex)}
          role="button"
          tabIndex={0}
          aria-label="Büyütmek için tıklayın"
          onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") openDialog(activeIndex); }}
        >
          {currentImage && (
            <Image
              src={currentImage}
              alt={title}
              fill
              priority
              className="object-cover transition-transform duration-100"
              style={
                isZoomed
                  ? { transform: "scale(1.5)", transformOrigin: zoomOrigin }
                  : undefined
              }
            />
          )}
          <div className="absolute top-3 right-3 bg-background/70 rounded-md p-1 backdrop-blur-sm">
            <ZoomIn className="h-4 w-4 text-foreground" />
          </div>
        </div>

        {/* Thumbnail strip */}
        {allImages.length > 1 && (
          <div className="relative group/thumbs">
            {allImages.length > 5 && (
              <button
                type="button"
                aria-label="Önceki"
                onClick={() => scrollThumbs("left")}
                className="hidden group-hover/thumbs:flex absolute left-0 top-1/2 -translate-y-1/2 z-10 h-7 w-7 items-center justify-center rounded-full bg-background border shadow-sm"
              >
                <ChevronLeft className="h-3.5 w-3.5" />
              </button>
            )}
            <div
              ref={thumbsRef as React.RefObject<HTMLDivElement>}
              className="flex gap-2 overflow-x-auto scrollbar-hide"
            >
              {allImages.map((img, i) => (
                <button
                  key={i}
                  type="button"
                  aria-label={`Görsel ${i + 1}`}
                  onClick={() => setActiveIndex(i)}
                  onKeyDown={(e) => { if (e.key === "Enter") setActiveIndex(i); }}
                  className={cn(
                    "relative h-16 w-16 shrink-0 rounded-md overflow-hidden border-2 transition-colors",
                    i === activeIndex ? "border-primary" : "border-border hover:border-muted-foreground",
                  )}
                >
                  <Image src={img} alt={`${title} ${i + 1}`} fill className="object-cover" />
                </button>
              ))}
            </div>
            {allImages.length > 5 && (
              <button
                type="button"
                aria-label="Sonraki"
                onClick={() => scrollThumbs("right")}
                className="hidden group-hover/thumbs:flex absolute right-0 top-1/2 -translate-y-1/2 z-10 h-7 w-7 items-center justify-center rounded-full bg-background border shadow-sm"
              >
                <ChevronRight className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
        )}
      </div>

      {/* Mobile Embla carousel */}
      <div className="md:hidden">
        <div ref={emblaRef} className="overflow-hidden rounded-lg">
          <div className="flex">
            {allImages.map((img, i) => (
              <div key={i} className="flex-shrink-0 w-full relative aspect-square bg-secondary">
                <Image src={img} alt={`${title} ${i + 1}`} fill className="object-cover" />
              </div>
            ))}
          </div>
        </div>
        {allImages.length > 1 && (
          <div className="flex justify-center gap-1.5 mt-3">
            {allImages.map((_, i) => (
              <button
                key={i}
                type="button"
                aria-label={`Görsel ${i + 1}`}
                onClick={() => emblaApi?.scrollTo(i)}
                className={cn(
                  "h-1.5 rounded-full transition-all duration-200",
                  i === mobileIndex ? "w-5 bg-primary" : "w-1.5 bg-muted-foreground/40",
                )}
              />
            ))}
          </div>
        )}
      </div>

      {/* Full-screen dialog */}
      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-3xl p-0 bg-black/95 border-0">
          <div className="relative aspect-square">
            {dialogImage && (
              <Image
                src={dialogImage}
                alt={title}
                fill
                className="object-contain"
              />
            )}
            {allImages.length > 1 && (
              <>
                <button
                  type="button"
                  aria-label="Önceki görsel"
                  onClick={dialogPrev}
                  className="absolute left-3 top-1/2 -translate-y-1/2 h-9 w-9 rounded-full bg-white/20 flex items-center justify-center text-white hover:bg-white/30 transition-colors"
                >
                  <ChevronLeft className="h-5 w-5" />
                </button>
                <button
                  type="button"
                  aria-label="Sonraki görsel"
                  onClick={dialogNext}
                  className="absolute right-3 top-1/2 -translate-y-1/2 h-9 w-9 rounded-full bg-white/20 flex items-center justify-center text-white hover:bg-white/30 transition-colors"
                >
                  <ChevronRight className="h-5 w-5" />
                </button>
              </>
            )}
            <div className="absolute bottom-3 right-4 text-white/70 text-sm">
              {dialogIndex + 1} / {allImages.length}
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
