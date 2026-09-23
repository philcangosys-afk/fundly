import { useMemo, useState } from 'react'
import type { ColumnDef } from '@/lib/schema'
import { cellText, formatAmount, formatDate, formatDateTime } from '@/lib/format'

interface DataTableProps {
  columns: ColumnDef[]
  rows: Record<string, unknown>[]
  onOpen?: (row: Record<string, unknown>) => void
  pageSize?: number
}

function renderCell(column: ColumnDef, value: unknown) {
  switch (column.type) {
    case 'amount':
      return formatAmount(value)
    case 'date':
      return formatDate(value)
    case 'datetime':
      return formatDateTime(value)
    case 'bool':
      return value ? 'نعم' : 'لا'
    case 'url':
      return value ? (
        <a
          href={String(value)}
          target="_blank"
          rel="noreferrer"
          onClick={(event) => event.stopPropagation()}
          className="font-extrabold text-brand underline-offset-2 hover:underline"
        >
          فتح
        </a>
      ) : (
        '—'
      )
    case 'id':
      return value ? (
        <span className="font-mono text-[10.5px] text-ink-muted">{String(value).slice(0, 8)}…</span>
      ) : (
        '—'
      )
    case 'json': {
      if (!value) return '—'
      const keys = typeof value === 'object' ? Object.keys(value as object).length : 0
      if (Array.isArray(value)) return `${value.length} عنصر`
      return keys ? `${keys} حقل` : '—'
    }
    default:
      return cellText(value)
  }
}

/** جدول بصفحات — الأعمدة الأساسية فقط، والباقي يُفتح في لوحة السجل. */
export default function DataTable({ columns, rows, onOpen, pageSize = 25 }: DataTableProps) {
  const [page, setPage] = useState(0)
  const visibleColumns = useMemo(() => {
    const primary = columns.filter((column) => column.primary)
    return primary.length ? primary : columns.slice(0, 7)
  }, [columns])

  const pages = Math.max(1, Math.ceil(rows.length / pageSize))
  const current = Math.min(page, pages - 1)
  const slice = rows.slice(current * pageSize, current * pageSize + pageSize)

  return (
    <div>
      <div className="overflow-x-auto rounded-xl border border-hairline">
        <table className="w-full border-collapse text-right">
          <thead>
            <tr className="bg-[#f3f7f6]">
              {visibleColumns.map((column) => (
                <th
                  key={column.key}
                  scope="col"
                  className="whitespace-nowrap px-3 py-2.5 text-[11px] font-black text-ink-body"
                >
                  {column.label}
                </th>
              ))}
              {onOpen && <th className="w-10 px-2" />}
            </tr>
          </thead>
          <tbody>
            {slice.map((row, index) => (
              <tr
                key={String(row.id ?? index)}
                onClick={() => onOpen?.(row)}
                className={`border-t border-hairline ${
                  onOpen ? 'cursor-pointer transition-colors hover:bg-brand-soft/60' : ''
                }`}
              >
                {visibleColumns.map((column) => (
                  <td
                    key={column.key}
                    className="max-w-[260px] px-3 py-2.5 align-top text-[12px] font-semibold text-ink-title"
                  >
                    <div className="cell-clamp leading-relaxed">{renderCell(column, row[column.key])}</div>
                  </td>
                ))}
                {onOpen && (
                  <td className="px-2 text-center text-ink-muted" aria-hidden>
                    ‹
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {pages > 1 && (
        <nav className="mt-3 flex items-center justify-between gap-3">
          <span className="text-[11.5px] font-bold text-ink-muted">
            صفحة {current + 1} من {pages} · {rows.length} سجل
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setPage(Math.max(0, current - 1))}
              disabled={current === 0}
              className="rounded-xl bg-[#f3f7f6] px-4 py-2 text-[11.5px] font-extrabold text-ink-title disabled:opacity-40"
            >
              السابق
            </button>
            <button
              type="button"
              onClick={() => setPage(Math.min(pages - 1, current + 1))}
              disabled={current >= pages - 1}
              className="rounded-xl bg-[#f3f7f6] px-4 py-2 text-[11.5px] font-extrabold text-ink-title disabled:opacity-40"
            >
              التالي
            </button>
          </div>
        </nav>
      )}
    </div>
  )
}
