import type { ReactNode } from "react";
import { MoreHorizontal } from "lucide-react";
import { formatNumber } from "@/lib/format";

interface MetricCardProps {
  title: string;
  value: number | string;
  detail?: string;
  icon: ReactNode;
  iconClass: string;
  loading?: boolean;
}

/** بطاقة رقم واحد — نفس بطاقة التصميم، لكن قيمتها من قاعدة البيانات. */
export default function MetricCard({
  title,
  value,
  detail,
  icon,
  iconClass,
  loading = false,
}: MetricCardProps) {
  return (
    <div className="metric-card">
      <div className="flex items-start justify-between gap-3">
        <div className={`metric-icon ${iconClass}`}>{icon}</div>
        <MoreHorizontal className="h-5 w-5 text-hairline" aria-hidden />
      </div>
      <p className="mt-4 text-[13px] font-medium text-ink-body">{title}</p>
      <p className="mt-1 text-[27px] font-extrabold tracking-tight text-ink-title">
        {loading ? "…" : typeof value === "number" ? formatNumber(value) : value}
      </p>
      {detail && <p className="mt-1 text-[11px] text-ink-muted">{detail}</p>}
    </div>
  );
}
