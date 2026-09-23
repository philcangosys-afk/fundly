/** تنسيقات عربية موحّدة — الأرقام إنجليزية والتواريخ يوم/شهر/سنة. */

const numberFormat = new Intl.NumberFormat('en-US')

export function formatNumber(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '0'
  return numberFormat.format(value)
}

export function formatAmount(value: unknown): string {
  const n = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(n)) return '—'
  return numberFormat.format(Math.round(n * 100) / 100)
}

export function formatDate(value: unknown): string {
  if (!value) return '—'
  const date = new Date(String(value))
  if (Number.isNaN(date.getTime())) return String(value)
  return `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`
}

export function formatDateTime(value: unknown): string {
  if (!value) return '—'
  const date = new Date(String(value))
  if (Number.isNaN(date.getTime())) return String(value)
  const time = `${String(date.getHours()).padStart(2, '0')}:${String(
    date.getMinutes(),
  ).padStart(2, '0')}`
  return `${formatDate(value)} · ${time}`
}

/** «قبل 3 أيام» بدل تاريخ خام في أماكن النشاط. */
export function relativeTime(value: unknown): string {
  if (!value) return '—'
  const date = new Date(String(value))
  if (Number.isNaN(date.getTime())) return '—'
  const diff = Date.now() - date.getTime()
  const day = 86_400_000
  if (diff < 3_600_000) return 'خلال الساعة'
  if (diff < day) return `قبل ${Math.floor(diff / 3_600_000)} ساعة`
  if (diff < 30 * day) return `قبل ${Math.floor(diff / day)} يوم`
  if (diff < 365 * day) return `قبل ${Math.floor(diff / (30 * day))} شهر`
  return `قبل ${Math.floor(diff / (365 * day))} سنة`
}

export function daysUntil(value: unknown): number | null {
  if (!value) return null
  const date = new Date(String(value))
  if (Number.isNaN(date.getTime())) return null
  const today = new Date()
  const midnight = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  return Math.round((date.getTime() - midnight.getTime()) / 86_400_000)
}

/** مفتاح شهري YYYY-MM للتجميع الزمني. */
export function monthKey(value: unknown): string | null {
  if (!value) return null
  const date = new Date(String(value))
  if (Number.isNaN(date.getTime())) return null
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`
}

const monthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
]

export function monthLabel(key: string): string {
  const [year, month] = key.split('-')
  const index = Number(month) - 1
  return `${monthNames[index] ?? month} ${year.slice(2)}`
}

/** عرض أي قيمة داخل خلية جدول بصيغة مقروءة. */
export function cellText(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—'
  if (typeof value === 'boolean') return value ? 'نعم' : 'لا'
  if (typeof value === 'object') {
    const keys = Object.keys(value as object)
    return keys.length === 0 ? '—' : `${keys.length} حقل`
  }
  const text = String(value)
  if (/^\d{4}-\d{2}-\d{2}(T|$)/.test(text)) return formatDate(text)
  return text
}
