import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/*
  المفتاح العام (anon) مصمَّم ليكون ظاهرًا في العميل — وهو أصلًا مضمَّن في
  تطبيق fundly نفسه. الحماية الحقيقية من سياسات RLS لا من إخفائه. أما مفتاح
  service_role فلا يوضع هنا أبدًا؛ ما يحتاجه يُنفَّذ في server/.

  القيم أدناه احتياطية فقط: ملف .env يتقدّم عليها إن وُجد.
*/
const FALLBACK_URL = 'https://pcppwpbaknxflzbqbrxj.supabase.co'
const FALLBACK_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBjcHB3cGJha254Zmx6YnFicnhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NDkwMDcsImV4cCI6MjEwMDAyNTAwN30.kyUladJf7EUZeVhtjJDfnEPbHPiqKx8ovyRSbBEL0Is'

const url =
  (import.meta.env.VITE_SUPABASE_URL as string | undefined) || FALLBACK_URL
const anonKey =
  (import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined) ||
  FALLBACK_ANON_KEY

/** إعدادات ناقصة تُعرض كرسالة واضحة بدل شاشة بيضاء. */
export const configError =
  !url || !anonKey
    ? 'رابط المشروع أو المفتاح العام مفقود — أضف VITE_SUPABASE_URL و VITE_SUPABASE_ANON_KEY في .env.'
    : null

export const supabaseUrl = url

export const supabase: SupabaseClient = createClient(
  url,
  anonKey,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      storageKey: 'fundly-admin-session',
    },
  },
)

/** رسالة خطأ عربية مفهومة بدل نص PostgREST الخام. */
export function readableError(error: unknown): string {
  const message =
    typeof error === 'object' && error && 'message' in error
      ? String((error as { message: unknown }).message)
      : String(error)
  if (message.includes('does not exist') || message.includes('schema cache')) {
    return 'هذا الجدول غير موجود في قاعدة البيانات.'
  }
  if (message.includes('permission denied') || message.includes('RLS')) {
    return 'لا صلاحية لقراءة هذا الجدول بهذا الحساب (سياسة RLS).'
  }
  if (message.includes('Invalid login credentials')) {
    return 'البريد أو كلمة المرور غير صحيحة.'
  }
  if (message.includes('Failed to fetch')) {
    return 'تعذّر الوصول إلى الخادم — تحقّق من الاتصال ومن رابط المشروع.'
  }
  return message
}
