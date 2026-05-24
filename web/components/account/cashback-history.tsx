"use client";

import { useState } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";
import { Pagination } from "@/components/catalog/pagination";
import { formatPrice } from "@/lib/money";
import { useCashbackHistoryQuery } from "@/lib/account/queries";
import { cn } from "@/lib/utils";

const YEAR_FILTERS = [
  { key: "all", label: "Hepsi" },
  { key: "current", label: "Bu yıl" },
  { key: "last", label: "Geçen yıl" },
] as const;

type YearFilter = (typeof YEAR_FILTERS)[number]["key"];

function getDateRange(filter: YearFilter): { from?: string; to?: string } {
  const now = new Date();
  const year = now.getFullYear();
  if (filter === "current") {
    return { from: `${year}-01-01`, to: `${year}-12-31` };
  }
  if (filter === "last") {
    return { from: `${year - 1}-01-01`, to: `${year - 1}-12-31` };
  }
  return {};
}

function periodLabel(yyyymm: string): string {
  const year = parseInt(yyyymm.slice(0, 4), 10);
  const month = parseInt(yyyymm.slice(4, 6), 10) - 1;
  return new Date(year, month, 1).toLocaleDateString("tr-TR", {
    month: "long",
    year: "numeric",
  });
}

export function CashbackHistory() {
  const [yearFilter, setYearFilter] = useState<YearFilter>("all");
  const [page, setPage] = useState(1);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const dateRange = getDateRange(yearFilter);
  const { data, isLoading, isError } = useCashbackHistoryQuery({
    ...dateRange,
    page,
  });

  const totalPages = data ? Math.ceil(data.total / (data.per_page || 12)) : 0;

  return (
    <div className="space-y-4">
      {/* Year filter chips */}
      <div className="flex gap-2 flex-wrap">
        {YEAR_FILTERS.map(({ key, label }) => (
          <button
            key={key}
            type="button"
            onClick={() => {
              setYearFilter(key);
              setPage(1);
            }}
            className={cn(
              "px-3 py-1.5 rounded-full text-sm font-medium transition-colors",
              yearFilter === key
                ? "bg-primary text-primary-foreground"
                : "bg-muted text-muted-foreground hover:text-foreground",
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {/* History list */}
      {isLoading && (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="h-14 rounded-lg bg-muted animate-pulse" />
          ))}
        </div>
      )}

      {isError && (
        <p className="text-sm text-muted-foreground py-4 text-center">
          Geçmiş yüklenemedi.
        </p>
      )}

      {data && data.items.length === 0 && (
        <p className="text-sm text-muted-foreground py-8 text-center">
          Bu dönemde cashback bulunamadı.
        </p>
      )}

      {data && data.items.length > 0 && (
        <div className="divide-y divide-border rounded-lg border border-border overflow-hidden">
          {data.items.map((item) => {
            const isExpanded = expandedId === item.id;
            return (
              <div key={item.id}>
                <button
                  type="button"
                  onClick={() => setExpandedId(isExpanded ? null : item.id)}
                  className="flex w-full items-center justify-between px-4 py-3 hover:bg-accent/50 transition-colors text-left"
                >
                  <div>
                    <p className="text-sm font-medium text-foreground">
                      {periodLabel(item.period_yyyymm)}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {item.order_count} sipariş
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="text-sm font-semibold text-success">
                      +{formatPrice(item.amount_minor, "TRY_COIN")}
                    </span>
                    <span
                      className={cn(
                        "text-xs px-2 py-0.5 rounded-full font-medium",
                        item.status === "paid"
                          ? "bg-success/10 text-success"
                          : "bg-muted text-muted-foreground",
                      )}
                    >
                      {item.status === "paid" ? "Ödendi" : "Beklemede"}
                    </span>
                    {isExpanded ? (
                      <ChevronUp className="h-4 w-4 text-muted-foreground shrink-0" />
                    ) : (
                      <ChevronDown className="h-4 w-4 text-muted-foreground shrink-0" />
                    )}
                  </div>
                </button>

                {isExpanded && item.orders && item.orders.length > 0 && (
                  <div className="px-4 pb-3 space-y-1 bg-muted/30">
                    {item.orders.map((o) => (
                      <div key={o.id} className="flex justify-between text-xs py-1">
                        <span className="text-muted-foreground">#{o.order_number}</span>
                        <span className="font-medium text-foreground">
                          {formatPrice(o.amount_minor, "TRY_COIN")}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {totalPages > 1 && (
        <Pagination
          currentPage={page}
          totalPages={totalPages}
          onPageChange={setPage}
        />
      )}
    </div>
  );
}
