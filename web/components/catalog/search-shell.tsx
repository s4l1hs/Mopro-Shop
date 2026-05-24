"use client";

import { Clock, SearchX } from "lucide-react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { useCategories } from "@/lib/catalog/categories-cache";
import { CatalogShell } from "./catalog-shell";

const STORAGE_KEY = "mopro-recent-searches";
const MAX_RECENT = 5;

function saveSearch(q: string) {
  if (typeof window === "undefined") return;
  try {
    const existing: unknown = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "[]");
    const arr = Array.isArray(existing) ? (existing as string[]) : [];
    const next = [q, ...arr.filter((s) => s !== q)].slice(0, MAX_RECENT);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // ignore storage errors
  }
}

function loadRecent(): string[] {
  if (typeof window === "undefined") return [];
  try {
    const raw: unknown = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "[]");
    return Array.isArray(raw) ? (raw as string[]) : [];
  } catch {
    return [];
  }
}

export function SearchShell() {
  const searchParams = useSearchParams();
  const q = searchParams.get("q")?.trim() ?? "";
  const { data: categories } = useCategories();
  const [recentSearches, setRecentSearches] = useState<string[]>([]);

  useEffect(() => {
    setRecentSearches(loadRecent());
  }, []);

  useEffect(() => {
    if (q) {
      saveSearch(q);
      setRecentSearches(loadRecent());
    }
  }, [q]);

  const topCategories = (categories ?? [])
    .filter((c) => c.parent_id === null)
    .slice(0, 5);

  if (!q) {
    return (
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-12">
        {recentSearches.length > 0 && (
          <div className="mb-8">
            <h2 className="text-sm font-medium text-muted-foreground mb-3 flex items-center gap-1.5">
              <Clock className="h-3.5 w-3.5" />
              Son aramalar
            </h2>
            <div className="flex flex-wrap gap-2">
              {recentSearches.map((s) => (
                <Link
                  key={s}
                  href={`/search?q=${encodeURIComponent(s)}`}
                  className="text-sm px-3 py-1.5 rounded-full border border-border hover:bg-accent transition-colors text-foreground"
                >
                  {s}
                </Link>
              ))}
            </div>
          </div>
        )}
        <p className="text-muted-foreground text-sm">
          Aramak istediğiniz ürünü girin.
        </p>
      </div>
    );
  }

  const emptyContent = (
    <div className="flex flex-col items-center gap-4 py-16 text-center">
      <SearchX className="h-14 w-14 text-muted-foreground/30" />
      <p className="text-muted-foreground">
        <strong className="text-foreground">&ldquo;{q}&rdquo;</strong> için sonuç bulunamadı.
      </p>
      {topCategories.length > 0 && (
        <div className="mt-2">
          <p className="text-sm text-muted-foreground mb-3">Önerilen aramalar:</p>
          <div className="flex flex-wrap gap-2 justify-center">
            {topCategories.map((cat) => (
              <Link
                key={cat.id}
                href={`/categories/${cat.slug}`}
                className="text-sm px-3 py-1.5 rounded-full border border-border hover:bg-accent transition-colors text-foreground"
              >
                {cat.name}
              </Link>
            ))}
          </div>
        </div>
      )}
    </div>
  );

  return (
    <CatalogShell
      headerContent={
        <h1 className="text-2xl font-bold text-foreground">
          <span className="text-primary">&ldquo;{q}&rdquo;</span> için sonuçlar
        </h1>
      }
      queryBase={`/products?q=${encodeURIComponent(q)}`}
      emptyContent={emptyContent}
    />
  );
}
