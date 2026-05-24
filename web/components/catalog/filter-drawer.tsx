"use client";

import { SlidersHorizontal } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { FilterSidebar } from "./filter-sidebar";
import type { FilterState, ProductFacets } from "@/lib/catalog/products-list-cache";

interface FilterDrawerProps {
  filters: FilterState;
  facets?: ProductFacets;
  resultCount: number;
  onChange: (update: Partial<FilterState>) => void;
  onClear: () => void;
}

export function FilterDrawer({
  filters,
  facets,
  resultCount,
  onChange,
  onClear,
}: FilterDrawerProps) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button
        variant="outline"
        className="lg:hidden gap-2"
        onClick={() => setOpen(true)}
      >
        <SlidersHorizontal className="h-4 w-4" />
        Filtrele
      </Button>

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="right" className="flex flex-col p-0 w-80 max-w-[85vw]">
          <SheetHeader className="px-5 pt-5 pb-4 border-b border-border shrink-0">
            <SheetTitle>Filtreler</SheetTitle>
          </SheetHeader>

          <div className="flex-1 overflow-y-auto px-5">
            <FilterSidebar
              filters={filters}
              {...(facets !== undefined && { facets })}
              onChange={onChange}
              onClear={() => {
                onClear();
                setOpen(false);
              }}
            />
          </div>

          <div className="shrink-0 border-t border-border px-5 py-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
            <Button className="w-full" onClick={() => setOpen(false)}>
              Sonuçları göster ({resultCount.toLocaleString("tr-TR")})
            </Button>
          </div>
        </SheetContent>
      </Sheet>
    </>
  );
}
