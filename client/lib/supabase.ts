import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/*
  المفتاح العام (anon) مصمَّم ليكون ظاهرًا في العميل — وهو أصلًا مضمَّن في
  تطبيق fundly نفسه. الحماية الحقيقية من سياسات RLS لا من إخفائه. أما مفتاح
  service_role فلا يوضع هنا أبدًا؛ ما يحتاجه يُنفَّذ في server/.

  القيم أدناه احتياطية: ملف .env يتقدّم عليها إن كانت قيمته سليمة.
*/
const FALLBACK_URL = 'https://pcppwpbaknxflzbqbrxj.supabase.co'
const FALLBACK_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBjcHB3cGJha254Zmx6YnFicnhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NDkwMDcsImV4cCI6MjEwMDAyNTAwN30.kyUladJf7EUZeVhtjJDfnEPbHPiqKx8ovyRSbBEL0Is'

/** يزيل المسافات وعلامات الاقتباس التي تلتصق بالقيمة عند النسخ في .env. */
function clean(value: unknown): string {
  return String(value ?? '')
    .trim()
    .replace(/^['"]|['"]$/g, '')
    .trim()
}

/**
 * مفتاح anon سليم هو JWT من ثلاثة أجزاء تفصلها نقطتان. قيمة مبتورة أو
 * ملفوفة على سطرين في .env تُنتج «Invalid API key» بلا تفسير — فتُتجاهل
 * ويُستعمل المفتاح المضمَّن بدلًا منها.
 */
function isJwtLike(value: string): boolean {
  const parts = value.split('.')
  return parts.length === 3 && parts.every((part) => part.length > 10)
}

const envUrl = clean(import.meta.env.VITE_SUPABASE_URL)
const envKey = clean(import.meta.env.VITE_SUPABASE_ANON_KEY)

const urlIsValid = /^https?:\/\/[^\s/]+/.test(envUrl)
const keyIsValid = isJwtLike(envKey)

/** الشرطة المائلة في آخر الرابط تكسر بعض المسارات، فتُقطع. */
export const supabaseUrl = (urlIsValid ? envUrl : FALLBACK_URL).replace(/\/+$/, '')

const anonKey = keyIsValid ? envKey : FALLBACK_ANON_KEY

/** من أين جاء المفتاح — يظهر في شاشة الدخول لتشخيص أخطاء المفتاح. */
export const keySource: 'env' | 'built-in' = keyIsValid ? 'env' : 'built-in'

/** تحذير يُعرض حين توجد في .env قيمة لكنها غير سليمة. */
export const configError =
  envKey.length > 0 && !keyIsValid
    ? 'قيمة VITE_SUPABASE_ANON_KEY في .env غير سليمة (مبتورة أو مقسومة على سطرين) — استُعمل المفتاح المضمَّن بدلًا منها.'
    : envUrl.length > 0 && !urlIsValid
      ? 'قيمة VITE_SUPABASE_URL في .env غير سليمة — استُعمل الرابط المضمَّن بدلًا منها.'
      : null

export const supabase: SupabaseClient = createClient(supabaseUrl, anonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    storageKey: 'fundly-admin-session',
  },
})

/** رسالة خطأ عربية مفهومة بدل نص PostgREST الخام. */
export function readableError(error: unknown): string {
  const message =
    typeof error === 'object' && error && 'message' in error
      ? String((error as { message: unknown }).message)
      : String(error)
  if (message.includes('Invalid API key')) {
    return 'المفتاح العام مرفوض من الخادم — تحقّق من VITE_SUPABASE_ANON_KEY في .env، أو احذف السطر لاستعمال المفتاح المضمَّن.'
  }
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
