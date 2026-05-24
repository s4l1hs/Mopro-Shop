import { cn } from "@/lib/utils";
import type { OrderStatus } from "@/lib/types/account";

const STATUS_CONFIG: Record<
  OrderStatus,
  { label: string; className: string }
> = {
  pending_payment: {
    label: "Ödeme bekleniyor",
    className: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400",
  },
  paid: {
    label: "Hazırlanıyor",
    className: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400",
  },
  shipped: {
    label: "Kargoda",
    className: "bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400",
  },
  delivered: {
    label: "Teslim edildi",
    className: "bg-success/15 text-success",
  },
  cancelled: {
    label: "İptal edildi",
    className: "bg-muted text-muted-foreground",
  },
  refunded: {
    label: "İade edildi",
    className: "bg-destructive/10 text-destructive",
  },
};

interface OrderStatusPillProps {
  status: OrderStatus;
  className?: string;
}

export function OrderStatusPill({ status, className }: OrderStatusPillProps) {
  const config = STATUS_CONFIG[status];
  return (
    <span
      className={cn(
        "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
        config.className,
        className,
      )}
    >
      {config.label}
    </span>
  );
}
