import { useMemo, useState } from 'react'
import Card from '@/components/admin/Card'
import StatTile from '@/components/admin/StatTile'
import Status from '@/components/admin/Status'
import Toolbar from '@/components/admin/Toolbar'
import PageHeader from '@/components/admin/PageHeader'
import BarList from '@/components/admin/charts/BarList'
import TrendChart from '@/components/admin/charts/TrendChart'
import { useRows } from '@/lib/useRows'
import { formatDate, formatNumber, relativeTime } from '@/lib/format'
import { groupCount, monthlySeries, sumColumn } from '@/lib/stats'

export default function Documents() {
  const documents = useRows('document_records', { orderBy: 'created_at', limit: 1000 })
  const attachments = useRows('commitment_attachments', { orderBy: 'uploaded_at', limit: 1000 })

  const [query, setQuery] = useState('')
  const [typeFilter, setTypeFilter] = useState('الكل')

  const types = useMemo(() => {
    const values = new Set<string>()
    documents.rows.forEach((row) => {
      const value = String(row.doc_type ?? '').trim()
      if (value) values.add(value)
    })
    return ['الكل', ...[...values].sort()]
  }, [documents.rows])

  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase()
    return documents.rows.filter((row) => {
      if (typeFilter !== 'الكل' && String(row.doc_type ?? '') !== typeFilter) return false
      if (!term) return true
      return [row.doc_type, row.doc_number, row.linked_label].some((value) =>
        String(value ?? '').toLowerCase().includes(term),
      )
    })
  }, [documents.rows, query, typeFilter])

  const byType = useMemo(() => groupCount(documents.rows, 'doc_type'), [documents.rows])
  const trend = useMemo(() => monthlySeries(documents.rows, 'created_at', 12), [documents.rows])
  const storageKb = useMemo(
    () => sumColumn(attachments.rows, 'file_size_kb'),
    [attachments.rows],
  )

  const heaviest = useMemo(
    () =>
      [...attachments.rows]
        .sort((a, b) => Number(b.file_size_kb ?? 0) - Number(a.file_size_kb ?? 0))
        .slice(0, 8),
    [attachments.rows],
  )

  return (
    <>
      <PageHeader
        title="المستندات والمرفقات"
        hint="المستندات المنشأة من القوالب، والملفات المرفوعة على الالتزامات وأحجامها."
      />

      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatTile label="المستندات" value={documents.rows.length} icon="🗎" tone="brand" />
        <StatTile label="المرفقات" value={attachments.rows.length} icon="📎" />
        <StatTile
          label="المساحة المستهلكة"
          value={`${formatNumber(Math.round(storageKb / 1024))} م.ب`}
          icon="⛁"
          tone="gold"
        />
        <StatTile label="أنواع المستندات" value={Math.max(0, types.length - 1)} icon="◫" />
      </div>

      <div className="mb-5 grid gap-4 lg:grid-cols-5">
        <Card title="المستندات المُنشأة شهريًا" className="lg:col-span-3">
          {documents.loading ? (
            <Status state="loading" />
          ) : documents.error ? (
            <Status state="error" message={documents.error} onRetry={documents.reload} />
          ) : (
            <TrendChart data={trend} measure="مستند" />
          )}
        </Card>

        <Card title="حسب النوع" className="lg:col-span-2">
          {documents.loading ? <Status state="loading" /> : <BarList data={byType} limit={7} />}
        </Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-5">
        <Card title="سجل المستندات" className="lg:col-span-3">
          <Toolbar
            query={query}
            onQuery={setQuery}
            filterLabel="النوع"
            filterValue={typeFilter}
            filterOptions={types}
            onFilter={setTypeFilter}
          />
          {documents.loading ? (
            <Status state="loading" />
          ) : filtered.length === 0 ? (
            <Status state="empty" message="لا توجد مستندات مطابقة" />
          ) : (
            <ul className="divide-y divide-hairline">
              {filtered.slice(0, 40).map((row, index) => (
                <li key={String(row.id ?? index)} className="flex items-start gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12.5px] font-extrabold text-ink-title">
                      {String(row.doc_type ?? 'مستند')}{' '}
                      {row.doc_number ? `· ${row.doc_number}` : ''}
                    </p>
                    <p className="mt-0.5 truncate text-[10.5px] font-bold text-ink-muted">
                      {String(row.linked_label ?? '—')}
                    </p>
                  </div>
                  <span className="shrink-0 text-[10.5px] font-bold text-ink-muted">
                    {formatDate(row.issued_on ?? row.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card
          title="أكبر المرفقات"
          hint="أول ما يُراجَع حين ترتفع فاتورة التخزين."
          className="lg:col-span-2"
        >
          {attachments.loading ? (
            <Status state="loading" />
          ) : attachments.error ? (
            <Status state="error" message={attachments.error} onRetry={attachments.reload} />
          ) : heaviest.length === 0 ? (
            <Status state="empty" message="لا توجد مرفقات" />
          ) : (
            <ul className="divide-y divide-hairline">
              {heaviest.map((row, index) => (
                <li key={String(row.id ?? index)} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[12px] font-extrabold text-ink-title">
                      {String(row.file_name ?? row.title ?? '—')}
                    </p>
                    <p className="mt-0.5 text-[10.5px] font-bold text-ink-muted">
                      {relativeTime(row.uploaded_at)}
                    </p>
                  </div>
                  <span className="shrink-0 text-[11px] font-black tabular-nums text-ink-body">
                    {formatNumber(Math.round(Number(row.file_size_kb ?? 0)))} ك.ب
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </>
  )
}
