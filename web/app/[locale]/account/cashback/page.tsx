"use client";

import { Clock, Coins, ChevronDown, ChevronUp } from "lucide-react";
import { useState } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { CashbackChart } from "@/components/account/cashback-chart";
import { CashbackHistory } from "@/components/account/cashback-history";
import { formatPrice } from "@/lib/money";
import {
  useCashbackContributorsQuery,
  useCashbackSummaryQuery,
} from "@/lib/account/queries";

function daysUntilNextFirst(): number {
  const now = new Date();
  const next = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  return Math.ceil((next.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
}

function daysElapsedInMonth(): number {
  return new Date().getDate() - 1;
}

function daysInCurrentMonth(): number {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
}

function ContributorsAccordion() {
  const [open, setOpen] = useState(false);
  const { data, isLoading } = useCashbackContributorsQuery();

  const count = data?.length ?? 0;

  return (
    <div className="rounded-lg border border-border overflow-hidden">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between px-4 py-3 bg-muted/40 hover:bg-muted/60 transition-colors text-left"
      >
        <span className="text-sm font-medium text-foreground">
          Aktif siparişlerinden gelen cashback&apos;ler ({count})
        </span>
        {open ? (
          <ChevronUp className="h-4 w-4 text-muted-foreground" />
        ) : (
          <ChevronDown className="h-4 w-4 text-muted-foreground" />
        )}
      </button>

      {open && (
        <div className="divide-y divide-border">
          {isLoading && (
            <div className="px-4 py-3 space-y-2">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-8 rounded" />
              ))}
            </div>
          )}
          {!isLoading && count === 0 && (
            <p className="px-4 py-4 text-sm text-muted-foreground">
              Henüz aktif cashback kaynağı yok.
            </p>
          )}
          {data?.map((c) => (
            <div key={c.order_id} className="flex items-center justify-between px-4 py-3">
              <div>
                <p className="text-sm font-medium text-foreground">
                  #{c.order_number}
                </p>
                <p className="text-xs text-muted-foreground">
                  {c.months_active} ay aktif
                </p>
              </div>
              <span className="text-sm font-semibold text-primary">
                {formatPrice(c.monthly_amount_minor, "TRY_COIN")}/ay
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function CashbackPage() {
  const { data, isLoading } = useCashbackSummaryQuery();

  const daysElapsed = daysElapsedInMonth();
  const daysTotal = daysInCurrentMonth();
  const progressPct = Math.min(100, Math.round((daysElapsed / daysTotal) * 100));
  const daysLeft = daysUntilNextFirst();

  const nextPayoutDate = data?.next_payout_date
    ? new Date(data.next_payout_date).toLocaleDateString("tr-TR", {
        day: "numeric",
        month: "long",
        year: "numeric",
      })
    : null;

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold text-foreground">Cashback Cüzdanım</h1>

      {/* Hero card */}
      <div className="rounded-2xl bg-gradient-to-br from-primary to-primary/70 text-white p-6 md:p-10">
        {isLoading ? (
          <div className="space-y-3">
            <Skeleton className="h-4 w-48 bg-white/20 rounded" />
            <Skeleton className="h-16 w-64 bg-white/20 rounded" />
            <Skeleton className="h-4 w-36 bg-white/20 rounded" />
          </div>
        ) : (
          <>
            <p className="text-sm font-medium opacity-80 mb-2">
              Toplam Aylık Cashback&apos;in
            </p>
            <p className="text-5xl md:text-7xl font-bold mb-1">
              {formatPrice(data?.total_monthly_minor ?? 0, "TRY_COIN")}
            </p>
            <p className="text-lg font-medium opacity-90 mb-6">
              / ay
            </p>
            <p className="text-sm opacity-75 mb-6">
              {data?.active_plan_count ?? 0} aktif siparişten geliyor
            </p>
            <div className="grid sm:grid-cols-2 gap-4 border-t border-white/20 pt-6">
              <div>
                <p className="text-xs opacity-70">Bugüne kadar kazandığın</p>
                <p className="text-xl font-bold">
                  {formatPrice(data?.total_earned_minor ?? 0, "TRY_COIN")}
                </p>
              </div>
              <div>
                <p className="text-xs opacity-70">Önümüzdeki ay alacağın</p>
                <p className="text-xl font-bold">
                  {formatPrice(data?.next_payout_minor ?? 0, "TRY_COIN")}
                </p>
              </div>
            </div>
          </>
        )}
      </div>

      {/* Next payout strip */}
      <div className="rounded-lg border border-border p-4 space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <Clock className="h-5 w-5 text-primary" />
            <div>
              <p className="text-sm font-medium text-foreground">Sıradaki ödemen</p>
              <p className="text-xs text-muted-foreground">{nextPayoutDate ?? "—"}</p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-lg font-bold text-primary">
              {formatPrice(data?.next_payout_minor ?? 0, "TRY_COIN")}
            </p>
            <p className="text-xs text-muted-foreground">{daysLeft} gün sonra</p>
          </div>
        </div>
        <div className="h-2 bg-muted rounded-full overflow-hidden">
          <div
            className="h-full bg-primary rounded-full transition-all"
            style={{ width: `${progressPct}%` }}
          />
        </div>
        <p className="text-xs text-muted-foreground text-right">{progressPct}% tamamlandı</p>
      </div>

      {/* Chart */}
      {data?.chart_data && data.chart_data.length > 0 && (
        <div className="rounded-lg border border-border p-4">
          <h2 className="text-sm font-semibold text-foreground mb-4 flex items-center gap-2">
            <Coins className="h-4 w-4 text-primary" />
            Son 12 Ay
          </h2>
          <CashbackChart data={data.chart_data} />
          <div className="flex gap-4 mt-2 justify-end">
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <span className="h-2 w-4 rounded-full bg-primary inline-block opacity-60" />
              Kazanılan
            </div>
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <span className="h-0 w-4 border-t-2 border-dashed border-primary inline-block" />
              Beklenen
            </div>
          </div>
        </div>
      )}

      {/* Active contributors accordion */}
      <ContributorsAccordion />

      {/* History */}
      <div>
        <h2 className="text-lg font-semibold text-foreground mb-4">Cashback Geçmişin</h2>
        <CashbackHistory />
      </div>
    </div>
  );
}
