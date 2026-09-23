import { formatNumber } from '@/lib/format'

interface BarListProps {
  data: { label: string; value: number }[]
  /** ما تقيسه الأشرطة — يظهر في التلميحة. */
  measure?: string
  max?: number
  limit?: number
  emptyText?: string
}

/**
 * ترتيب بالمقدار: قياس واحد فلونه واحد (الهوية ليست المعنى هنا، المقدار هو).
 * كل شريط يحمل قيمته مكتوبة، فلا يعتمد القارئ على الطول وحده.
 */
export default function BarList({
  data,
  measure = 'سجل',
  max,
  limit = 8,
  emptyText = 'لا توجد بيانات',
}: BarListProps) {
  const rows = data.slice(0, limit)
  const ceiling = max ?? Math.max(1, ...rows.map((row) => row.value))

  if (rows.length === 0) {
    return <p className="py-8 text-center text-[12px] font-bold text-ink-muted">{emptyText}</p>
  }

  return (
    <ul className="space-y-3">
      {rows.map((row) => {
        const ratio = Math.max(0.02, row.value / ceiling)
        return (
          <li key={row.label} title={`${row.label}: ${formatNumber(row.value)} ${measure}`}>
            <div className="mb-1.5 flex items-baseline gap-2">
              <span className="min-w-0 flex-1 truncate text-[12px] font-extrabold text-ink-title">
                {row.label}
              </span>
              <span className="text-[12px] font-black tabular-nums text-ink-body">
                {formatNumber(row.value)}
              </span>
            </div>
            <div className="h-2 w-full overflow-hidden rounded-full bg-[#f3f7f6]">
              <div
                className="h-full rounded-full transition-[width] duration-500"
                style={{ width: `${ratio * 100}%`, background: 'var(--series-1)' }}
              />
            </div>
          </li>
        )
      })}
    </ul>
  )
}
