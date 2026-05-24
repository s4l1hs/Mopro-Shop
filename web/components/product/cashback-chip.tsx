import { Coins } from "lucide-react";
import { cashbackMonthlyMinor } from "@/lib/money";
import { cn } from "@/lib/utils";

export interface CashbackChipProps {
  priceMinor: number;
  commissionBps: number;
  size?: "sm" | "md";
  className?: string;
}

export function CashbackChip({ priceMinor, commissionBps, size = "md", className }: CashbackChipProps) {
  const monthly = cashbackMonthlyMinor(priceMinor, commissionBps);
  if (monthly <= 0) return null;

  const amount = (monthly / 100).toLocaleString("tr-TR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full bg-primary/10 text-primary font-medium",
        size === "sm" ? "px-2 py-0.5 text-xs" : "px-2.5 py-1 text-xs",
        className,
      )}
    >
      <Coins className={cn("shrink-0", size === "sm" ? "h-3 w-3" : "h-3.5 w-3.5")} />
      <span>Aylık {amount} TL Mopro Coin</span>
    </span>
  );
}
