import { monthKey } from './format'

/** سلسلة شهرية من صفوف تحمل عمود تاريخ — للرسم الزمني. */
export function monthlySeries(
  rows: Record<string, unknown>[],
  dateColumn: string,
  months = 12,
): { key: string; label: string; value: number }[] {
  const counts = new Map<string, number>()
  rows.forEach((row) => {
    const key = monthKey(row[dateColumn])
    if (!key) return
    counts.set(key, (counts.get(key) ?? 0) + 1)
  })

  const now = new Date()
  const series: { key: string; label: string; value: number }[] = []
  for (let index = months - 1; index >= 0; index -= 1) {
    const date = new Date(now.getFullYear(), now.getMonth() - index, 1)
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`
    series.push({ key, label: key, value: counts.get(key) ?? 0 })
  }
  return series
}

/** تجميع عدّي حسب قيمة عمود — لقوائم الأشرطة. */
export function groupCount(
  rows: Record<string, unknown>[],
  column: string,
  emptyLabel = 'بلا تصنيف',
): { label: string; value: number }[] {
  const counts = new Map<string, number>()
  rows.forEach((row) => {
    const raw = row[column]
    const label = raw === null || raw === undefined || raw === '' ? emptyLabel : String(raw)
    counts.set(label, (counts.get(label) ?? 0) + 1)
  })
  return [...counts.entries()]
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value)
}

export function sumColumn(rows: Record<string, unknown>[], column: string): number {
  return rows.reduce((total, row) => {
    const value = Number(row[column])
    return Number.isFinite(value) ? total + value : total
  }, 0)
}
