import { useMemo, useState } from 'react'
import Card from '@/components/admin/Card'
import StatTile from '@/components/admin/StatTile'
import Status from '@/components/admin/Status'
import Toolbar from '@/components/admin/Toolbar'
import PageHeader from '@/components/admin/PageHeader'
import BarList from '@/components/admin/charts/BarList'
import { useRows } from '@/lib/useRows'
import { daysUntil, formatDate } from '@/lib/format'
import { groupCount } from '@/lib/stats'
import { supabase, readableError } from '@/lib/supabase'

type State = 'ساري' | 'قارب الانتهاء' | 'منتهٍ' | 'موقوف' | 'مجدول'

function stateOf(row: Record<string, unknown>): State {
  if (row.is_paused) return 'موقوف'
  const end = daysUntil(row.end_date)
  const start = daysUntil(row.start_date)
  if (end !== null && end < 0) return 'منتهٍ'
  if (start !== null && start > 0) return 'مجدول'
  if (end !== null && end <= 30) return 'قارب الانتهاء'
  return 'ساري'
}

const tone: Record<State, string> = {
  'ساري': 'bg-brand-soft text-brand-dark',
  'قارب الانتهاء': 'bg-gold-soft text-gold-dark',
  'منتهٍ': 'bg-[#FBE7E4] text-[#C4392E]',
  'موقوف': 'bg-[#f3f7f6] text-ink-muted',
  'مجدول': 'bg-[#f3f7f6] text-ink-body',
}

export default function Delegations() {
  const { rows, loading, error, reload } = useRows('delegations', {
    orderBy: 'created_at',
    limit: 1000,
  })
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState('الكل')
  const [busyId, setBusyId] = useState<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  const withState = useMemo(
    () => rows.map((row) => ({ row, state: stateOf(row) })),
    [rows],
  )

  const filtered = useMemo(() => {
    const term = query.trim().toLowerCase()
    return withState.filter((item) => {
      if (filter !== 'الكل' && item.state !== filter) return false
      if (!term) return true
      return [item.row.delegate_name, item.row.scope, item.row.notes].some((value) =>
        String(value ?? '').toLowerCase().includes(term),
      )
    })
  }, [withState, query, filter])

  const byScope = useMemo(
    () =>
      groupCount(
        rows.map((row) => ({ scope: String(row.scope ?? '').split(' — ')[0] })),
        'scope',
      ),
    [rows],
  )

  const counts = useMemo(() => {
    const map = new Map<State, number>()
    withState.forEach((item) => map.set(item.state, (map.get(item.state) ?? 0) + 1))
    return map
  }, [withState])

  const togglePause = async (row: Record<string, unknown>) => {
    const id = row.id
    if (!id) return
    setBusyId(String(id))
    setActionError(null)
    const result = await supabase
      .from('delegations')
      .update({ is_paused: !row.is_paused })
      .eq('id', id)
    setBusyId(null)
    if (result.error) {
      setActionError(readableError(result.error))
      return
    }
    reload()
  }

  return (
    <>
      <PageHeader
        title="التفويضات"
        hint="من فُوِّض، وعلى أي نطاق، وبأي صلاحية، ولأي مدة — ومن انتهى تفويضه ولم يُجدَّد."
      />

      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatTile label="الإجمالي" value={rows.length} icon="⚖" tone="brand" />
        <StatTile label="سارية" value={counts.get('ساري') ?? 0} icon="✓" />
        <StatTile
          label="قاربت الانتهاء"
          value={counts.get('قارب الانتهاء') ?? 0}
          icon="⏳"
          tone="gold"
        />
        <StatTile label="منتهية" value={counts.get('منتهٍ') ?? 0} icon="✕" tone="danger" />
      </div>

      <div className="mb-5 grid gap-4 lg:grid-cols-5">
        <Card title="التفويضات حسب النطاق" className="lg:col-span-2">
          {loading ? <Status state="loading" /> : <BarList data={byScope} limit={8} />}
        </Card>

        <Card className="lg:col-span-3">
          <Toolbar
            query={query}
            onQuery={setQuery}
            filterLabel="الحالة"
            filterValue={filter}
            filterOptions={['الكل', 'ساري', 'قارب الانتهاء', 'منتهٍ', 'موقوف', 'مجدول']}
            onFilter={setFilter}
          />

          {actionError && (
            <p className="mb-3 rounded-xl bg-[#FBE7E4] px-3 py-2 text-[11.5px] font-extrabold text-[#C4392E]">
              {actionError}
            </p>
          )}

          {loading ? (
            <Status state="loading" />
          ) : error ? (
            <Status state="error" message={error} onRetry={reload} />
          ) : filtered.length === 0 ? (
            <Status state="empty" message="لا يوجد تفويض مطابق" />
          ) : (
            <ul className="divide-y divide-hairline">
              {filtered.map((item, index) => {
                const remaining = daysUntil(item.row.end_date)
                const permissions = Array.isArray(item.row.permissions)
                  ? (item.row.permissions as unknown[]).length
                  : 0
                return (
                  <li key={String(item.row.id ?? index)} className="py-3">
                    <div className="flex items-start gap-3">
                      <div className="min-w-0 flex-1">
                        <p className="text-[13px] font-black text-ink-title">
                          {String(item.row.delegate_name ?? '—')}
                        </p>
                        <p className="mt-1 text-[11.5px] font-bold leading-relaxed text-ink-body">
                          {String(item.row.scope ?? '—')}
                        </p>
                        <p className="mt-1 text-[11px] font-semibold text-ink-muted">
                          {permissions} صلاحية ·{' '}
                          {item.row.end_date
                            ? `من ${formatDate(item.row.start_date)} إلى ${formatDate(item.row.end_date)}`
                            : `من ${formatDate(item.row.start_date)} · مفتوح`}
                        </p>
                      </div>
                      <div className="flex shrink-0 flex-col items-end gap-2">
                        <span
                          className={`rounded-full px-2.5 py-1 text-[10.5px] font-black ${tone[item.state]}`}
                        >
                          {item.state === 'قارب الانتهاء' && remaining !== null
                            ? `${remaining} يوم`
                            : item.state}
                        </span>
                        <button
                          type="button"
                          onClick={() => void togglePause(item.row)}
                          disabled={busyId === String(item.row.id)}
                          className="rounded-xl bg-[#f3f7f6] px-3 py-1.5 text-[10.5px] font-extrabold text-ink-body disabled:opacity-50"
                        >
                          {item.row.is_paused ? 'تشغيل' : 'إيقاف'}
                        </button>
                      </div>
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </Card>
      </div>
    </>
  )
}
