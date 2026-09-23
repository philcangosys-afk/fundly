import { useMemo } from 'react'
import Card from '@/components/admin/Card'
import StatTile from '@/components/admin/StatTile'
import Status from '@/components/admin/Status'
import PageHeader from '@/components/admin/PageHeader'
import { useRows } from '@/lib/useRows'
import { daysUntil } from '@/lib/format'

interface Check {
  label: string
  detail: string
  count: number
  /** الأعلى أخطر. */
  severity: 'critical' | 'warn' | 'ok'
}

function severityOf(count: number, warnAt = 1): Check['severity'] {
  if (count === 0) return 'ok'
  return count >= warnAt ? 'warn' : 'ok'
}

export default function Health() {
  const personal = useRows('personal_entries', { limit: 1000 })
  const shared = useRows('shared_entries', { limit: 1000 })
  const assets = useRows('project_assets', { limit: 1000 })
  const assetEntries = useRows('project_asset_entries', { limit: 1000 })
  const contracts = useRows('property_unit_contracts', { limit: 1000 })
  const unitPayments = useRows('property_unit_payments', { limit: 1000 })
  const wallets = useRows('wallets', { limit: 500 })
  const walletTx = useRows('wallet_transactions', { limit: 1000 })
  const delegations = useRows('delegations', { limit: 500 })

  const loading =
    personal.loading ||
    shared.loading ||
    assets.loading ||
    assetEntries.loading ||
    contracts.loading ||
    unitPayments.loading ||
    walletTx.loading ||
    delegations.loading

  const checks = useMemo<Check[]>(() => {
    const assetIds = new Set(assets.rows.map((row) => String(row.id)))
    const contractIds = new Set(contracts.rows.map((row) => String(row.id)))
    const walletIds = new Set(wallets.rows.map((row) => String(row.id)))

    const orphanEntries = assetEntries.rows.filter(
      (row) => row.asset_id && !assetIds.has(String(row.asset_id)),
    ).length

    const orphanPayments = unitPayments.rows.filter(
      (row) => row.contract_id && !contractIds.has(String(row.contract_id)),
    ).length

    const orphanTx = walletTx.rows.filter(
      (row) => row.wallet_id && !walletIds.has(String(row.wallet_id)),
    ).length

    const untitled = [...personal.rows, ...shared.rows].filter(
      (row) => !String(row.title ?? '').trim(),
    ).length

    const noUser = [
      ...personal.rows,
      ...shared.rows,
      ...assets.rows,
      ...contracts.rows,
      ...wallets.rows,
    ].filter((row) => !row.user_id).length

    const expiredDelegations = delegations.rows.filter((row) => {
      const days = daysUntil(row.end_date)
      return days !== null && days < 0 && !row.is_paused
    }).length

    const contractsEnded = contracts.rows.filter((row) => {
      const days = daysUntil(row.end_date)
      return days !== null && days < 0 && String(row.status ?? '') !== 'منتهي'
    }).length

    const zeroAmount = [...personal.rows, ...shared.rows].filter(
      (row) => Number(row.amount ?? 0) === 0,
    ).length

    return [
      {
        label: 'بنود أصول بلا أصل',
        detail: 'سجل في project_asset_entries يشير إلى أصل محذوف — يظهر في العدّادات ولا يُفتح.',
        count: orphanEntries,
        severity: orphanEntries > 0 ? 'critical' : 'ok',
      },
      {
        label: 'دفعات بلا عقد',
        detail: 'دفعة في property_unit_payments مرتبطة بعقد لم يعد موجودًا.',
        count: orphanPayments,
        severity: orphanPayments > 0 ? 'critical' : 'ok',
      },
      {
        label: 'حركات بلا محفظة',
        detail: 'حركة في wallet_transactions تشير إلى محفظة محذوفة، فيختل رصيدها.',
        count: orphanTx,
        severity: orphanTx > 0 ? 'critical' : 'ok',
      },
      {
        label: 'سجلات بلا حساب',
        detail: 'صف بلا user_id — لن تراه أي سياسة RLS بعد فصل الحسابات.',
        count: noUser,
        severity: noUser > 0 ? 'critical' : 'ok',
      },
      {
        label: 'التزامات بلا عنوان',
        detail: 'يظهر في القوائم كسطر فارغ، ولا يُعثر عليه بالبحث.',
        count: untitled,
        severity: severityOf(untitled),
      },
      {
        label: 'تفويضات منتهية لم تُوقف',
        detail: 'انتهت مدتها وما زالت مفعّلة في السجل.',
        count: expiredDelegations,
        severity: severityOf(expiredDelegations),
      },
      {
        label: 'عقود انتهت وحالتها غير منتهية',
        detail: 'تاريخ الانتهاء مضى لكن الحالة لم تُحدَّث.',
        count: contractsEnded,
        severity: severityOf(contractsEnded),
      },
      {
        label: 'التزامات بمبلغ صفر',
        detail: 'قد تكون مقصودة (مهمة أو مستند)، وقد تكون إدخالًا ناقصًا.',
        count: zeroAmount,
        severity: 'ok',
      },
    ]
  }, [
    personal.rows,
    shared.rows,
    assets.rows,
    assetEntries.rows,
    contracts.rows,
    unitPayments.rows,
    wallets.rows,
    walletTx.rows,
    delegations.rows,
  ])

  const critical = checks.filter((check) => check.severity === 'critical' && check.count > 0)
  const warnings = checks.filter((check) => check.severity === 'warn' && check.count > 0)
  const clean = checks.filter((check) => check.count === 0)

  return (
    <>
      <PageHeader
        title="سلامة البيانات"
        hint="فحوصات تكشف الصفوف اليتيمة والناقصة قبل أن تظهر للمستخدم كأرقام لا تُفسَّر."
      />

      <div className="mb-5 grid grid-cols-3 gap-3">
        <StatTile label="مشاكل حرجة" value={critical.length} icon="✕" tone="danger" />
        <StatTile label="تنبيهات" value={warnings.length} icon="!" tone="gold" />
        <StatTile label="فحوصات سليمة" value={clean.length} icon="✓" tone="brand" />
      </div>

      <Card title="نتائج الفحص">
        {loading ? (
          <Status state="loading" />
        ) : (
          <ul className="divide-y divide-hairline">
            {[...critical, ...warnings, ...checks.filter((c) => c.count > 0 && c.severity === 'ok'), ...clean].map(
              (check) => (
                <li key={check.label} className="flex items-start gap-3 py-3">
                  <span
                    aria-hidden
                    className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-xl text-[13px] font-black ${
                      check.count === 0
                        ? 'bg-brand-soft text-brand-dark'
                        : check.severity === 'critical'
                          ? 'bg-[#FBE7E4] text-[#C4392E]'
                          : 'bg-gold-soft text-gold-dark'
                    }`}
                  >
                    {check.count === 0 ? '✓' : check.severity === 'critical' ? '✕' : '!'}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="text-[12.5px] font-black text-ink-title">{check.label}</p>
                    <p className="mt-1 text-[11.5px] font-medium leading-relaxed text-ink-muted">
                      {check.detail}
                    </p>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-2.5 py-1 text-[11px] font-black tabular-nums ${
                      check.count === 0
                        ? 'bg-[#f3f7f6] text-ink-muted'
                        : check.severity === 'critical'
                          ? 'bg-[#FBE7E4] text-[#C4392E]'
                          : 'bg-gold-soft text-gold-dark'
                    }`}
                  >
                    {check.count}
                  </span>
                </li>
              ),
            )}
          </ul>
        )}
      </Card>
    </>
  )
}
