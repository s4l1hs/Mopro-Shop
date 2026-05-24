"use client";

import { cn } from "@/lib/utils";

export const SORT_OPTIONS = [
  { value: "recommended", label: "Önerilen" },
  { value: "bestseller", label: "Çok satanlar" },
  { value: "newest", label: "En yeniler" },
  { value: "price_asc", label: "Fiyat: artan" },
  { value: "price_desc", label: "Fiyat: azalan" },
  { value: "cashback_desc", label: "Cashback: yüksek" },
] as const;

interface SortSelectProps {
  value: string;
  onChange: (value: string) => void;
  className?: string;
}

export function SortSelect({ value, onChange, className }: SortSelectProps) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className={cn(
        "h-10 rounded-md border border-input bg-background px-3 pr-8 text-sm font-medium text-foreground",
        "hover:bg-accent focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-1",
        "cursor-pointer",
        className,
      )}
    >
      {SORT_OPTIONS.map((opt) => (
        <option key={opt.value} value={opt.value}>
          {opt.label}
        </option>
      ))}
    </select>
  );
}
