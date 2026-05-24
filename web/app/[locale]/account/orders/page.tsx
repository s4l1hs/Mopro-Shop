"use client";

import Link from "next/link";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Pagination } from "@/components/catalog/pagination";
import { OrderCard } from "@/components/account/order-card";
import { useOrdersListQuery } from "@/lib/account/queries";
import { cn } from "@/lib/utils";

const FILTER_CHIPS = [
  { key: "all", label: "Tümü" },
  { key: "active", label: "Aktif" },
  { key: "completed", label: "Tamamlanan" },
  { key: "cancelled", label: "İptal edilen" },
] as const;

type FilterKey = (typeof FILTER_CHIPS)[number]["key"];

function OrdersContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  const filter = (searchParams.get("filter") ?? "all") as FilterKey;
  const q = searchParams.get("q") ?? "";
  const page = parseInt(searchParams.get("page") ?? "1", 10);

  const [localQ, setLocalQ] = useState(q);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const applySearch = useCallback(
    (value: string) => {
      const params = new URLSearchParams(searchParams.toString());
      if (value) params.set("q", value);
      else params.delete("q");
      params.set("page", "1");
      router.replace(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams],
  );

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => applySearch(localQ), 300);
    return () => clearTimeout(debounceRef.current);
  }, [localQ, applySearch]);

  const { data, isLoading, isError } = useOrdersListQuery({ filter, q, page });

  const updateFilter = (key: FilterKey) => {
    const params = new URLSearchParams(searchParams.toString());
    if (key === "all") params.delete("filter");
    else params.set("filter", key);
    params.set("page", "1");
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  const updatePage = (p: number) => {
    const params = new URLSearchParams(searchParams.toString());
    params.set("page", String(p));
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  const totalPages = data ? Math.ceil(data.total / (data.per_page || 10)) : 0;

  return (
    <div className="space-y-5">
      <h1 className="text-2xl font-bold text-foreground">Siparişlerim</h1>

      {/* Filter chips */}
      <div className="flex gap-2 flex-wrap">
        {FILTER_CHIPS.map(({ key, label }) => (
          <button
            key={key}
            type="button"
            onClick={() => updateFilter(key)}
            className={cn(
              "px-3 py-1.5 rounded-full text-sm font-medium transition-colors",
              filter === key
                ? "bg-primary text-primary-foreground"
                : "bg-muted text-muted-foreground hover:text-foreground",
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Search */}
      <Input
        placeholder="Sipariş no veya ürün ara..."
        value={localQ}
        onChange={(e) => setLocalQ(e.target.value)}
        className="max-w-sm"
      />

      {/* List */}
      {isLoading ? (
        <div className="space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-40 rounded-lg" />
          ))}
        </div>
      ) : isError ? (
        <p className="text-sm text-muted-foreground py-4">Siparişler yüklenemedi.</p>
      ) : !data?.orders || data.orders.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-muted-foreground text-sm mb-3">
            {filter === "all" ? "Henüz siparişin yok." : `${FILTER_CHIPS.find((c) => c.key === filter)?.label ?? ""} siparişin yok.`}
          </p>
          <Link href="/" className="text-sm text-primary hover:underline">
            Alışverişe başla →
          </Link>
        </div>
      ) : (
        <div className="space-y-3">
          {data.orders.map((order) => (
            <OrderCard key={order.id} order={order} />
          ))}
        </div>
      )}

      {totalPages > 1 && (
        <Pagination
          currentPage={page}
          totalPages={totalPages}
          onPageChange={updatePage}
        />
      )}
    </div>
  );
}

export default function OrdersPage() {
  return (
    <Suspense fallback={<div className="space-y-3">{Array.from({length:5}).map((_,i)=><Skeleton key={i} className="h-40 rounded-lg"/>)}</div>}>
      <OrdersContent />
    </Suspense>
  );
}
