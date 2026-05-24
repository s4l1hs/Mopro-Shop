import { Coins, RotateCcw, ShieldCheck, Truck } from "lucide-react";
import { cn } from "@/lib/utils";

const TRUST_ITEMS = [
  { icon: Truck, label: "Ücretsiz Kargo", sub: "150 TL üzeri siparişlerde" },
  { icon: ShieldCheck, label: "Güvenli Ödeme", sub: "256-bit SSL şifreleme" },
  { icon: RotateCcw, label: "Kolay İade", sub: "14 gün içinde iade hakkı" },
  { icon: Coins, label: "Süresiz Cashback", sub: "Her ay Mopro Coin kazan" },
] as const;

interface TrustBarProps {
  className?: string;
}

export function TrustBar({ className }: TrustBarProps) {
  return (
    <div
      className={cn(
        "grid grid-cols-2 sm:grid-cols-4 gap-4 py-5 px-5 rounded-xl border border-border bg-card",
        className,
      )}
    >
      {TRUST_ITEMS.map(({ icon: Icon, label, sub }) => (
        <div key={label} className="flex items-center gap-3">
          <div className="h-10 w-10 shrink-0 rounded-lg bg-primary/10 flex items-center justify-center">
            <Icon className="h-5 w-5 text-primary" />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-medium text-foreground">{label}</p>
            <p className="text-xs text-muted-foreground">{sub}</p>
          </div>
        </div>
      ))}
    </div>
  );
}
