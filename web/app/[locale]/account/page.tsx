"use client";

import { Clock, Coins, Package, TrendingUp } from "lucide-react";
import Link from "next/link";
import { Skeleton } from "@/components/ui/skeleton";
import { OrderCard } from "@/components/account/order-card";
import { formatPrice } from "@/lib/money";
import { useAccountSummaryQuery } from "@/lib/account/queries";

export default function AccountDashboard() {
  const { data, isLoading, isError } = useAccountSummaryQuery();

  const nextDate = data?.next_payout_date
    ? new Date(data.next_payout_date).toLocaleDateString("tr-TR", {
        day: "numeric",
        month: "long",
        year: "numeric",
      })
    : null;

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold text-foreground">Hesabım</h1>

      {/* Summary cards */}
      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-28 rounded-lg" />
          ))}
        </div>
      ) : isError ? (
        <p className="text-sm text-muted-foreground">Özet yüklenemedi.</p>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {/* Monthly cashback */}
          <Link
            href="/account/cashback"
            className="rounded-lg border border-border bg-primary/5 p-4 space-y-2 hover:border-primary/40 transition-colors"
          >
            <div className="flex items-center gap-2 text-primary">
              <Coins className="h-5 w-5" />
              <span className="text-xs font-medium">Aylık Cashback</span>
            </div>
            <p className="text-2xl font-bold text-primary">
              {formatPrice(data?.monthly_cashback_minor ?? 0, "TRY_COIN")}
              <span className="text-sm font-normal text-muted-foreground ml-1">/ ay</span>
            </p>
            <p className="text-xs text-muted-foreground">
              {data?.monthly_cashback_active_orders ?? 0} aktif siparişten
            </p>
          </Link>

          {/* Total earned */}
          <div className="rounded-lg border border-border p-4 space-y-2">
            <div className="flex items-center gap-2 text-muted-foreground">
              <TrendingUp className="h-5 w-5" />
              <span className="text-xs font-medium">Toplam Kazanılmış</span>
            </div>
            <p className="text-2xl font-bold text-foreground">
              {formatPrice(data?.total_earned_minor ?? 0, "TRY_COIN")}
            </p>
            <p className="text-xs text-muted-foreground">Bugüne kadar</p>
          </div>

          {/* Active orders */}
          <Link
            href="/account/orders?filter=active"
            className="rounded-lg border border-border p-4 space-y-2 hover:border-primary/40 transition-colors"
          >
            <div className="flex items-center gap-2 text-muted-foreground">
              <Package className="h-5 w-5" />
              <span className="text-xs font-medium">Aktif Siparişler</span>
            </div>
            <p className="text-2xl font-bold text-foreground">
              {data?.active_orders_count ?? 0}
            </p>
            <p className="text-xs text-muted-foreground">
              {data?.in_transit_count ?? 0} kargoda,{" "}
              {data?.preparing_count ?? 0} hazırlanıyor
            </p>
          </Link>

          {/* Next payout */}
          <div className="rounded-lg border border-border p-4 space-y-2">
            <div className="flex items-center gap-2 text-muted-foreground">
              <Clock className="h-5 w-5" />
              <span className="text-xs font-medium">Bekleyen Cashback</span>
            </div>
            <p className="text-2xl font-bold text-foreground">
              {formatPrice(data?.next_payout_minor ?? 0, "TRY_COIN")}
            </p>
            <p className="text-xs text-muted-foreground">
              {nextDate ?? "—"}
            </p>
          </div>
        </div>
      )}

      {/* Recent orders */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-foreground">Son Siparişler</h2>
          <Link
            href="/account/orders"
            className="text-sm text-primary hover:underline underline-offset-2"
          >
            Tümünü gör →
          </Link>
        </div>

        {isLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-36 rounded-lg" />
            ))}
          </div>
        ) : !data?.recent_orders || data.recent_orders.length === 0 ? (
          <div className="rounded-lg border border-border p-8 text-center">
            <p className="text-muted-foreground text-sm">Henüz siparişin yok.</p>
            <Link
              href="/"
              className="text-sm text-primary hover:underline mt-2 inline-block"
            >
              Alışverişe başla →
            </Link>
          </div>
        ) : (
          <div className="space-y-3">
            {data.recent_orders.slice(0, 5).map((order) => (
              <OrderCard key={order.id} order={order} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
