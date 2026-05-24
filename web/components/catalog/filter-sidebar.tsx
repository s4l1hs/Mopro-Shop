"use client";

import { ChevronDown } from "lucide-react";
import { type ReactNode, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import type { FilterState, ProductFacets } from "@/lib/catalog/products-list-cache";
import { cn } from "@/lib/utils";

const CASHBACK_OPTIONS = [
  { value: "", label: "Tümü" },
  { value: "10", label: "≥ %10" },
  { value: "15", label: "≥ %15" },
  { value: "20", label: "≥ %20" },
] as const;

interface SectionProps {
  title: string;
  isOpen: boolean;
  onToggle: () => void;
  children: ReactNode;
}

function Section({ title, isOpen, onToggle, children }: SectionProps) {
  return (
    <div className="border-b border-border py-3 last:border-0">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center justify-between text-sm font-medium text-foreground hover:text-primary transition-colors"
      >
        {title}
        <ChevronDown
          className={cn(
            "h-4 w-4 text-muted-foreground transition-transform duration-200",
            isOpen && "rotate-180",
          )}
        />
      </button>
      <div
        className={cn(
          "overflow-hidden transition-all duration-200",
          isOpen ? "max-h-96 pt-3" : "max-h-0",
        )}
      >
        {children}
      </div>
    </div>
  );
}

interface FilterSidebarProps {
  filters: FilterState;
  facets?: ProductFacets;
  onChange: (update: Partial<FilterState>) => void;
  onClear: () => void;
  className?: string;
}

export function FilterSidebar({
  filters,
  facets,
  onChange,
  onClear,
  className,
}: FilterSidebarProps) {
  const [openSections, setOpenSections] = useState({
    price: true,
    brands: true,
    cashback: true,
  });
  const [showAllBrands, setShowAllBrands] = useState(false);
  const [localMin, setLocalMin] = useState(filters.minPrice);
  const [localMax, setLocalMax] = useState(filters.maxPrice);

  type Section = keyof typeof openSections;
  const toggleSection = (s: Section) =>
    setOpenSections((prev) => ({ ...prev, [s]: !prev[s] }));

  const toggleBrand = (brand: string) => {
    const next = filters.brands.includes(brand)
      ? filters.brands.filter((b) => b !== brand)
      : [...filters.brands, brand];
    onChange({ brands: next, page: 1 });
  };

  const applyPrice = () =>
    onChange({ minPrice: localMin, maxPrice: localMax, page: 1 });

  const brands = facets?.brands ?? [];
  const visibleBrands = showAllBrands ? brands : brands.slice(0, 10);

  return (
    <aside className={cn("text-sm", className)}>
      {/* Price range */}
      <Section
        title="Fiyat aralığı"
        isOpen={openSections.price}
        onToggle={() => toggleSection("price")}
      >
        <div className="flex items-center gap-2">
          <Input
            placeholder="Min ₺"
            value={localMin}
            onChange={(e) => setLocalMin(e.target.value)}
            className="h-8 text-xs"
            type="number"
            min={0}
          />
          <span className="text-muted-foreground shrink-0 text-xs">–</span>
          <Input
            placeholder="Max ₺"
            value={localMax}
            onChange={(e) => setLocalMax(e.target.value)}
            className="h-8 text-xs"
            type="number"
            min={0}
          />
        </div>
        <Button
          variant="outline"
          className="mt-2 w-full h-8 text-xs"
          onClick={applyPrice}
        >
          Uygula
        </Button>
      </Section>

      {/* Brands */}
      <Section
        title="Marka"
        isOpen={openSections.brands}
        onToggle={() => toggleSection("brands")}
      >
        <div className="space-y-2">
          {visibleBrands.map(({ name, count }) => (
            <label key={name} className="flex items-center gap-2 cursor-pointer group">
              <input
                type="checkbox"
                className="h-3.5 w-3.5 accent-primary shrink-0"
                checked={filters.brands.includes(name)}
                onChange={() => toggleBrand(name)}
              />
              <span className="flex-1 text-muted-foreground group-hover:text-foreground transition-colors truncate">
                {name}
              </span>
              <span className="text-xs text-muted-foreground/60 shrink-0">({count})</span>
            </label>
          ))}
          {brands.length > 10 && (
            <button
              type="button"
              className="text-xs text-primary hover:underline"
              onClick={() => setShowAllBrands((p) => !p)}
            >
              {showAllBrands ? "Daha az göster" : "Daha fazla göster"}
            </button>
          )}
          {brands.length === 0 && (
            <p className="text-xs text-muted-foreground">Marka bilgisi yok</p>
          )}
        </div>
      </Section>

      {/* Cashback */}
      <Section
        title="Cashback oranı"
        isOpen={openSections.cashback}
        onToggle={() => toggleSection("cashback")}
      >
        <div className="space-y-2">
          {CASHBACK_OPTIONS.map((opt) => (
            <label key={opt.value} className="flex items-center gap-2 cursor-pointer">
              <input
                type="radio"
                name="cashback-filter"
                className="accent-primary"
                checked={filters.cashback === opt.value}
                onChange={() => onChange({ cashback: opt.value, page: 1 })}
              />
              <span className="text-muted-foreground">{opt.label}</span>
            </label>
          ))}
        </div>
      </Section>

      {/* Switches */}
      <div className="py-3 border-b border-border space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-sm text-foreground">Sadece kargo bedava</span>
          <Switch
            checked={filters.freeShipping}
            onCheckedChange={(v) => onChange({ freeShipping: v, page: 1 })}
          />
        </div>
        <div className="flex items-center justify-between">
          <span className="text-sm text-foreground">Stokta olanlar</span>
          <Switch
            checked={filters.inStock}
            onCheckedChange={(v) => onChange({ inStock: v, page: 1 })}
          />
        </div>
      </div>

      {/* Clear */}
      <div className="pt-4">
        <Button variant="outline" className="w-full" onClick={onClear}>
          Filtreleri temizle
        </Button>
      </div>
    </aside>
  );
}
