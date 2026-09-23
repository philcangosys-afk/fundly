import { useCallback, useEffect, useState } from 'react'
import { supabase, readableError } from './supabase'

export interface RowsState {
  rows: Record<string, unknown>[]
  count: number | null
  loading: boolean
  error: string | null
  reload: () => void
}

/**
 * يقرأ جدولًا كاملًا بـ `*` — لا قائمة أعمدة ثابتة — فعمود جديد في قاعدة
 * البيانات يظهر فورًا، وتغيير اسم عمود لا يكسر الصفحة.
 */
export function useRows(
  table: string,
  options: { orderBy?: string; limit?: number } = {},
): RowsState {
  const { orderBy, limit = 500 } = options
  const [rows, setRows] = useState<Record<string, unknown>[]>([])
  const [count, setCount] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [tick, setTick] = useState(0)

  const reload = useCallback(() => setTick((value) => value + 1), [])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)

    const run = async () => {
      let query = supabase.from(table).select('*', { count: 'exact' }).limit(limit)
      if (orderBy) query = query.order(orderBy, { ascending: false, nullsFirst: false })
      const result = await query
      if (cancelled) return
      if (result.error) {
        // الترتيب على عمود غير موجود يفشل — نعيد المحاولة بلا ترتيب بدل
        // أن تبقى الصفحة فارغة برسالة غامضة.
        if (orderBy && String(result.error.message).includes('column')) {
          const retry = await supabase.from(table).select('*', { count: 'exact' }).limit(limit)
          if (cancelled) return
          if (!retry.error) {
            setRows((retry.data ?? []) as Record<string, unknown>[])
            setCount(retry.count ?? null)
            setLoading(false)
            return
          }
        }
        setError(readableError(result.error))
        setRows([])
        setCount(null)
        setLoading(false)
        return
      }
      setRows((result.data ?? []) as Record<string, unknown>[])
      setCount(result.count ?? null)
      setLoading(false)
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [table, orderBy, limit, tick])

  return { rows, count, loading, error, reload }
}

/** عدّاد سريع بلا جلب الصفوف — لبطاقات النظرة العامة. */
export async function countRows(table: string): Promise<number | null> {
  const result = await supabase.from(table).select('*', { count: 'exact', head: true })
  if (result.error) return null
  return result.count ?? 0
}
