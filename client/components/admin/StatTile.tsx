import { formatNumber } from "@/lib/format";

interface StatTileProps {
  label: string;
  value: number | string;
  note?: string;
  tone?: "brand" | "gold" | "danger" | "plain";
  icon?: string;
}

const tones = {
  brand: "bg-brand-soft text-brand",
  gold: "bg-gold-soft text-gold-dark",
  danger: "bg-[#FBE7E4] text-[#C4392E]",
  plain: "bg-[#f3f7f6] text-ink-body",
};

export default function StatTile({ label, value, note, tone = "plain", icon }: StatTileProps) {
  return (
    <div className="metric-card">
      <div className="flex items-center gap-2">
        <span className={`metric-icon h-8 w-8 text-[15px] ${tones[tone]}`} aria-hidden>
          {icon ?? "•"}
        </span>
        <span className="text-[11.5px] font-bold leading-snug text-ink-muted">{label}</span>
      </div>
      <p className="mt-3 text-[26px] font-black leading-none text-ink-title">
        {typeof value === "number" ? formatNumber(value) : value}
      </p>
      {note && <p className="mt-2 text-[11px] font-semibold text-ink-muted">{note}</p>}
    </div>
  );
}
