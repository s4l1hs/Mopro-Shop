import { Check } from "lucide-react";
import { cn } from "@/lib/utils";
import type { OrderStatus } from "@/lib/types/account";

interface TimelineStep {
  key: OrderStatus | "paid";
  label: string;
}

const STEPS: TimelineStep[] = [
  { key: "pending_payment", label: "Sipariş alındı" },
  { key: "paid", label: "Ödeme onaylandı" },
  { key: "shipped", label: "Kargoya verildi" },
  { key: "delivered", label: "Teslim edildi" },
];

const STATUS_RANK: Record<string, number> = {
  pending_payment: 0,
  paid: 1,
  shipped: 2,
  delivered: 3,
};

interface OrderTimelineProps {
  status: OrderStatus;
  shippedAt?: string | undefined;
  deliveredAt?: string | undefined;
}

export function OrderTimeline({ status, shippedAt, deliveredAt }: OrderTimelineProps) {
  if (status === "cancelled" || status === "refunded") {
    return (
      <div className="flex items-center gap-2 py-4">
        <div className="h-8 w-8 rounded-full bg-destructive/15 flex items-center justify-center">
          <span className="text-destructive text-lg">✕</span>
        </div>
        <span className="text-sm font-medium text-destructive">
          {status === "cancelled" ? "Sipariş iptal edildi" : "Sipariş iade edildi"}
        </span>
      </div>
    );
  }

  const currentRank = STATUS_RANK[status] ?? 0;

  return (
    <ol className="relative flex flex-col gap-0">
      {STEPS.map((step, i) => {
        const stepRank = STATUS_RANK[step.key] ?? i;
        const done = stepRank < currentRank;
        const active = stepRank === currentRank;

        let dateLabel = "";
        if (step.key === "shipped" && shippedAt) {
          dateLabel = new Date(shippedAt).toLocaleDateString("tr-TR", {
            day: "numeric",
            month: "long",
          });
        } else if (step.key === "delivered" && deliveredAt) {
          dateLabel = new Date(deliveredAt).toLocaleDateString("tr-TR", {
            day: "numeric",
            month: "long",
          });
        }

        return (
          <li key={step.key} className="flex items-start gap-4 pb-6 last:pb-0 relative">
            {/* Connector line */}
            {i < STEPS.length - 1 && (
              <div
                className={cn(
                  "absolute left-3.5 top-7 bottom-0 w-0.5",
                  done ? "bg-primary" : "bg-border",
                )}
              />
            )}

            {/* Node */}
            <div
              className={cn(
                "relative z-10 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border-2 transition-colors",
                done
                  ? "bg-primary border-primary text-primary-foreground"
                  : active
                    ? "border-primary bg-background"
                    : "border-border bg-background",
              )}
            >
              {done ? (
                <Check className="h-3.5 w-3.5" />
              ) : active ? (
                <span className="h-2.5 w-2.5 rounded-full bg-primary animate-pulse" />
              ) : null}
            </div>

            {/* Label */}
            <div className="pt-0.5">
              <p
                className={cn(
                  "text-sm font-medium",
                  done || active ? "text-foreground" : "text-muted-foreground",
                )}
              >
                {step.label}
              </p>
              {dateLabel && (
                <p className="text-xs text-muted-foreground mt-0.5">{dateLabel}</p>
              )}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
