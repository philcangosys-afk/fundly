import type { ReactNode } from 'react'

interface ToolbarProps {
  query: string
  onQuery: (value: string) => void
  filterLabel?: string
  filterValue?: string
  filterOptions?: string[]
  onFilter?: (value: string) => void
  right?: ReactNode
}

/** صف واحد فوق الجدول: بحث ثم فلتر ثم الأزرار — كما في التطبيق. */
export default function Toolbar({
  query,
  onQuery,
  filterLabel,
  filterValue,
  filterOptions,
  onFilter,
  right,
}: ToolbarProps) {
  return (
    <div className="mb-4 flex flex-wrap items-center gap-2">
      <div className="relative min-w-[200px] flex-1">
        <input
          value={query}
          onChange={(event) => onQuery(event.target.value)}
          placeholder="ابحث…"
          className="w-full rounded-xl bg-[#f3f7f6] px-4 py-2.5 pe-9 text-[12.5px] font-semibold text-ink-title outline-none placeholder:text-ink-muted focus:ring-2 focus:ring-brand/30"
        />
        <span className="pointer-events-none absolute inset-y-0 end-3 flex items-center text-ink-muted" aria-hidden>
          ⌕
        </span>
      </div>

      {filterOptions && onFilter && (
        <label className="flex items-center gap-2 rounded-xl bg-[#f3f7f6] px-3 py-2">
          <span className="text-[11px] font-bold text-ink-muted">{filterLabel ?? 'الحالة'}</span>
          <select
            value={filterValue}
            onChange={(event) => onFilter(event.target.value)}
            className="bg-transparent text-[12px] font-extrabold text-ink-title outline-none"
          >
            {filterOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
      )}

      {right}
    </div>
  )
}
