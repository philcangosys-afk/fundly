import { useEffect, useState } from 'react'
import type { ColumnDef } from '@/lib/schema'
import { cellText, formatAmount, formatDate, formatDateTime } from '@/lib/format'
import { supabase, readableError } from '@/lib/supabase'

interface RecordDrawerProps {
  table: string
  columns: ColumnDef[]
  row: Record<string, unknown> | null
  onClose: () => void
  onChanged: () => void
}

function displayValue(column: ColumnDef, value: unknown): string {
  switch (column.type) {
    case 'amount':
      return formatAmount(value)
    case 'date':
      return formatDate(value)
    case 'datetime':
      return formatDateTime(value)
    case 'bool':
      return value ? 'نعم' : 'لا'
    default:
      return cellText(value)
  }
}

/**
 * لوحة جانبية تعرض السجل كاملًا، وتفتح حقول JSON كما كتبها التطبيق —
 * وهذا هو المهم: نصف بيانات fundly تعيش داخل عمود details.
 */
export default function RecordDrawer({
  table,
  columns,
  row,
  onClose,
  onChanged,
}: RecordDrawerProps) {
  const [deleting, setDeleting] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setConfirming(false)
    setError(null)
  }, [row])

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  if (!row) return null

  const jsonColumns = columns.filter(
    (column) => column.type === 'json' && row[column.key] && typeof row[column.key] === 'object',
  )
  const plainColumns = columns.filter((column) => column.type !== 'json')

  const remove = async () => {
    const id = row.id
    if (!id) {
      setError('هذا السجل بلا معرّف، فلا يمكن حذفه من هنا.')
      return
    }
    setDeleting(true)
    const result = await supabase.from(table).delete().eq('id', id)
    setDeleting(false)
    if (result.error) {
      setError(readableError(result.error))
      return
    }
    onChanged()
    onClose()
  }

  return (
    <div className="fixed inset-0 z-40 flex" role="dialog" aria-modal="true">
      <button
        type="button"
        aria-label="إغلاق"
        onClick={onClose}
        className="flex-1 bg-ink-title/25 backdrop-blur-[1px]"
      />
      <aside className="flex h-full w-full max-w-[460px] flex-col bg-white shadow-2xl">
        <header className="flex items-start gap-3 border-b border-hairline px-5 py-4">
          <div className="min-w-0 flex-1">
            <h2 className="text-[15px] font-black text-ink-title">تفاصيل السجل</h2>
            <p className="mt-1 font-mono text-[10.5px] text-ink-muted">{String(row.id ?? '—')}</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl bg-[#f3f7f6] px-3 py-1.5 text-[12px] font-extrabold text-ink-body"
          >
            إغلاق
          </button>
        </header>

        <div className="flex-1 overflow-y-auto px-5 py-4">
          <dl className="divide-y divide-hairline">
            {plainColumns.map((column) => (
              <div key={column.key} className="flex gap-3 py-2.5">
                <dt className="w-[42%] shrink-0 text-[11.5px] font-bold leading-relaxed text-ink-muted">
                  {column.label}
                </dt>
                <dd className="flex-1 break-words text-[12.5px] font-extrabold leading-relaxed text-ink-title">
                  {column.type === 'url' && row[column.key] ? (
                    <a
                      href={String(row[column.key])}
                      target="_blank"
                      rel="noreferrer"
                      className="text-brand underline-offset-2 hover:underline"
                    >
                      فتح المرفق
                    </a>
                  ) : (
                    displayValue(column, row[column.key])
                  )}
                </dd>
              </div>
            ))}
          </dl>

          {jsonColumns.map((column) => {
            const value = row[column.key] as Record<string, unknown> | unknown[]
            const entries: [string, unknown][] = Array.isArray(value)
              ? value.map((item, index) => [String(index + 1), item])
              : Object.entries(value)
            return (
              <section key={column.key} className="mt-5">
                <h3 className="mb-2 text-[12.5px] font-black text-ink-title">{column.label}</h3>
                {entries.length === 0 ? (
                  <p className="text-[11.5px] font-bold text-ink-muted">لا شيء</p>
                ) : (
                  <div className="divide-y divide-hairline rounded-xl border border-hairline bg-[#f3f7f6]">
                    {entries.map(([key, item]) => (
                      <div key={key} className="flex gap-3 px-3 py-2">
                        <span className="w-[42%] shrink-0 break-words text-[11px] font-bold leading-relaxed text-ink-muted">
                          {key}
                        </span>
                        <span className="flex-1 break-words text-[11.5px] font-extrabold leading-relaxed text-ink-title">
                          {typeof item === 'object' && item !== null
                            ? JSON.stringify(item)
                            : String(item ?? '—') || '—'}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </section>
            )
          })}
        </div>

        <footer className="border-t border-hairline px-5 py-4">
          {error && (
            <p className="mb-3 rounded-xl bg-[#FBE7E4] px-3 py-2 text-[11.5px] font-extrabold text-[#C4392E]">
              {error}
            </p>
          )}
          {confirming ? (
            <div className="flex gap-2">
              <button
                type="button"
                onClick={remove}
                disabled={deleting}
                className="flex-1 rounded-xl bg-[#C4392E] px-4 py-2.5 text-[12px] font-extrabold text-white disabled:opacity-60"
              >
                {deleting ? 'جارٍ الحذف…' : 'تأكيد الحذف نهائيًا'}
              </button>
              <button
                type="button"
                onClick={() => setConfirming(false)}
                className="rounded-xl bg-[#f3f7f6] px-4 py-2.5 text-[12px] font-extrabold text-ink-body"
              >
                تراجع
              </button>
            </div>
          ) : (
            <button
              type="button"
              onClick={() => setConfirming(true)}
              className="w-full rounded-xl border border-[#C4392E]/30 bg-[#FBE7E4] px-4 py-2.5 text-[12px] font-extrabold text-[#C4392E]"
            >
              حذف هذا السجل
            </button>
          )}
        </footer>
      </aside>
    </div>
  )
}
