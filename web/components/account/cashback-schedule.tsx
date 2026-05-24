"use client";

import { useState } from "react";
import { Coins } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatPrice } from "@/lib/money";
import type { CashbackPayment } from "@/lib/types/account";
import { cn } from "@/lib/utils";

function periodLabel(yyyymm: string): string {
  const year = parseInt(yyyymm.slice(0, 4), 10);
  const month = parseInt(yyyymm.slice(4, 6), 10) - 1;
  return new Date(year, month, 1).toLocaleDateString("tr-TR", {
    month: "long",
    year: "numeric",
  });
}

const STATUS_STYLES = {
  paid: "bg-success/10 text-success",
  pending: "bg-muted text-muted-foreground",
  current: "bg-primary/10 text-primary",
} as const;

const STATUS_LABELS = {
  paid: "Ödendi",
  pending: "Bekleniyor",
  current: "Bu ay",
} as const;

interface CashbackScheduleProps {
  schedule: CashbackPayment[];
  monthlyAmountMinor: number;
  planStatus: "active" | "cancelled" | "pending";
}

export function CashbackSchedule({
  schedule,
  monthlyAmountMinor,
  planStatus,
}: CashbackScheduleProps) {
  const [expanded, setExpanded] = useState(false);
  const visible = expanded ? schedule : schedule.slice(0, 12);
  const hasMore = schedule.length > 12;

  return (
    <div className="space-y-4">
      {/* Header stats */}
      <div className="rounded-lg bg-primary/5 border border-primary/20 p-4">
        <div className="flex items-center gap-2 mb-2">
          <Coins className="h-5 w-5 text-primary" />
          <h3 className="font-semibold text-foreground">Cashback Programın</h3>
        </div>
        <p className="text-2xl font-bold text-primary">
          {formatPrice(monthlyAmountMinor, "TRY_COIN")}
          <span className="text-sm font-normal text-muted-foreground ml-1">/ ay</span>
        </p>
        <p className="text-xs text-muted-foreground mt-1">
          {planStatus === "active"
            ? "Plan iptal edilene kadar her ay devam eder"
            : planStatus === "pending"
              ? "Teslimattan 3 iş günü sonra başlar"
              : "Plan iptal edilmiştir"}
        </p>
      </div>

      {/* Timeline rows */}
      <div className="divide-y divide-border rounded-lg border border-border overflow-hidden">
        {visible.map((payment, i) => {
          const isLast = planStatus === "cancelled" && i === schedule.length - 1;
          return (
            <div
              key={payment.period_yyyymm}
              className={cn(
                "flex items-center justify-between px-4 py-2.5",
                payment.status === "current" && "bg-primary/5",
              )}
            >
              <div>
                <p className="text-sm font-medium text-foreground">
                  {isLast ? "Son Ödeme — " : ""}
                  {periodLabel(payment.period_yyyymm)}
                </p>
                {payment.status === "paid" && payment.paid_at && (
                  <p className="text-xs text-muted-foreground">
                    {new Date(payment.paid_at).toLocaleDateString("tr-TR", {
                      day: "numeric",
                      month: "short",
                    })}
                  </p>
                )}
              </div>
              <div className="flex items-center gap-3">
                <span className="text-sm font-semibold text-foreground">
                  {formatPrice(payment.amount_minor, "TRY_COIN")}
                </span>
                <span
                  className={cn(
                    "text-xs px-2 py-0.5 rounded-full font-medium",
                    STATUS_STYLES[payment.status],
                  )}
                >
                  {STATUS_LABELS[payment.status]}
                </span>
              </div>
            </div>
          );
        })}

        {/* Perpetual indicator */}
        {planStatus === "active" && (
          <div className="px-4 py-3 bg-muted/40 flex items-center gap-2">
            <div className="flex gap-1">
              <span className="h-1.5 w-1.5 rounded-full bg-muted-foreground/40" />
              <span className="h-1.5 w-1.5 rounded-full bg-muted-foreground/40" />
              <span className="h-1.5 w-1.5 rounded-full bg-muted-foreground/40" />
            </div>
            <p className="text-xs text-muted-foreground">
              Plan süresiz devam eder
            </p>
          </div>
        )}
      </div>

      {hasMore && (
        <Button
          variant="outline"
          size="sm"
          className="w-full"
          onClick={() => setExpanded(!expanded)}
        >
          {expanded ? "Daha az göster" : `Daha fazla göster (${schedule.length - 12} ay daha)`}
        </Button>
      )}

      <p className="text-xs text-muted-foreground text-center">
        Aylık cashbackler her ayın 1&apos;inde hesap bakiyene yatırılır
      </p>
    </div>
  );
}
