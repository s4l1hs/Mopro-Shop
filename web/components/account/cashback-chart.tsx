"use client";

import {
  Area,
  CartesianGrid,
  ComposedChart,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { CashbackChartPoint } from "@/lib/types/account";

interface CashbackChartProps {
  data: CashbackChartPoint[];
}

function formatMinorShort(minor: number): string {
  if (minor === 0) return "0";
  const whole = minor / 100;
  if (whole >= 1000) return `${(whole / 1000).toFixed(1)}B`;
  return whole.toLocaleString("tr-TR", { maximumFractionDigits: 0 });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function CustomTooltip({ active, payload, label }: any) {
  if (!active || !payload || payload.length === 0) return null;
  return (
    <div className="rounded-lg border border-border bg-popover p-2.5 text-xs shadow-lg space-y-1">
      <p className="font-semibold text-popover-foreground">{label}</p>
      {/* eslint-disable-next-line @typescript-eslint/no-explicit-any */}
      {(payload as any[]).map((entry: { name: string; value: number; color: string }) => (
        <p key={entry.name} style={{ color: entry.color }}>
          {entry.name}:{" "}
          {(entry.value / 100).toLocaleString("tr-TR", { minimumFractionDigits: 2 })} Coin
        </p>
      ))}
    </div>
  );
}

export function CashbackChart({ data }: CashbackChartProps) {
  if (data.length === 0) {
    return (
      <div className="h-48 flex items-center justify-center text-sm text-muted-foreground">
        Henüz veri yok
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={200}>
      <ComposedChart data={data} margin={{ top: 4, right: 8, left: -8, bottom: 0 }}>
        <CartesianGrid
          strokeDasharray="3 3"
          stroke="var(--color-border, #e5e7eb)"
          vertical={false}
        />
        <XAxis
          dataKey="month"
          tick={{ fill: "var(--color-muted-foreground, #6b7280)", fontSize: 11 }}
          axisLine={false}
          tickLine={false}
        />
        <YAxis
          tick={{ fill: "var(--color-muted-foreground, #6b7280)", fontSize: 11 }}
          axisLine={false}
          tickLine={false}
          tickFormatter={formatMinorShort}
        />
        <Tooltip content={<CustomTooltip />} />
        <Area
          type="monotone"
          dataKey="earned_minor"
          name="Kazanılan"
          stroke="var(--color-primary, #7c3aed)"
          fill="var(--color-primary, #7c3aed)"
          fillOpacity={0.12}
          strokeWidth={2}
          dot={false}
          activeDot={{ r: 4 }}
        />
        <Line
          type="monotone"
          dataKey="expected_minor"
          name="Beklenen"
          stroke="var(--color-primary, #7c3aed)"
          strokeDasharray="5 5"
          strokeWidth={1.5}
          dot={false}
          activeDot={{ r: 3 }}
        />
      </ComposedChart>
    </ResponsiveContainer>
  );
}
