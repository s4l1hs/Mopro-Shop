"use client";

import { Search, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

const STORAGE_KEY = "mopro-recent-searches";
const MAX_RECENT = 5;

interface HeaderSearchProps {
  className?: string;
}

export function HeaderSearch({ className }: HeaderSearchProps) {
  const router = useRouter();
  const [value, setValue] = useState("");
  const [focused, setFocused] = useState(false);
  const [recentSearches, setRecentSearches] = useState<string[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) setRecentSearches(JSON.parse(stored) as string[]);
    } catch {
      // ignore
    }
  }, []);

  const saveSearch = (q: string) => {
    const trimmed = q.trim();
    if (!trimmed) return;
    const updated = [trimmed, ...recentSearches.filter((s) => s !== trimmed)].slice(0, MAX_RECENT);
    setRecentSearches(updated);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
    } catch {
      // ignore
    }
  };

  const handleSubmit = (q?: string) => {
    const query = (q ?? value).trim();
    if (!query) return;
    saveSearch(query);
    setFocused(false);
    router.push(`/search?q=${encodeURIComponent(query)}`);
  };

  const showDropdown = focused && recentSearches.length > 0 && !value;

  return (
    <div className={cn("relative", className)}>
      <div
        className={cn(
          "flex items-center gap-2 h-10 px-4 rounded-full bg-secondary border border-transparent transition-all",
          focused &&
            "border-ring ring-2 ring-ring ring-offset-2 ring-offset-background",
        )}
      >
        <Search className="h-4 w-4 text-muted-foreground shrink-0" />
        <input
          ref={inputRef}
          type="search"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setTimeout(() => setFocused(false), 150)}
          onKeyDown={(e) => {
            if (e.key === "Enter") handleSubmit();
          }}
          placeholder="Ürün, kategori veya marka ara..."
          className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground min-w-0"
        />
        {value && (
          <button
            type="button"
            onClick={() => {
              setValue("");
              inputRef.current?.focus();
            }}
            className="shrink-0 text-muted-foreground hover:text-foreground transition-colors"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
        <button
          type="button"
          onClick={() => handleSubmit()}
          className="shrink-0 text-xs font-medium text-primary hover:text-primary/80 transition-colors"
        >
          Ara
        </button>
      </div>

      {/* Recent searches dropdown */}
      {showDropdown && (
        <div className="absolute top-full left-0 right-0 mt-1.5 rounded-xl border border-border bg-popover text-popover-foreground shadow-lg z-50 overflow-hidden">
          <p className="px-4 pt-3 pb-1 text-xs font-medium text-muted-foreground">
            Son aramalar
          </p>
          {recentSearches.map((s) => (
            <button
              key={s}
              type="button"
              onMouseDown={() => handleSubmit(s)}
              className="flex w-full items-center gap-2.5 px-4 py-2 text-sm text-foreground hover:bg-accent transition-colors"
            >
              <Search className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
              {s}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
