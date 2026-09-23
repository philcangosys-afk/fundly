import Card from '@/components/admin/Card'
import PageHeader from '@/components/admin/PageHeader'
import { supabaseUrl } from '@/lib/supabase'
import { TABLES } from '@/lib/schema'

export default function Settings() {
  return (
    <>
      <PageHeader
        title="الإعدادات"
        hint="معلومات الاتصال بقاعدة البيانات، وما تحتاجه اللوحة لتتوسّع لاحقًا."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="الاتصال">
          <dl className="divide-y divide-hairline">
            <div className="flex gap-3 py-2.5">
              <dt className="w-[40%] text-[11.5px] font-bold text-ink-muted">مشروع Supabase</dt>
              <dd dir="ltr" className="flex-1 break-all text-[11.5px] font-extrabold text-ink-title">
                {supabaseUrl}
              </dd>
            </div>
            <div className="flex gap-3 py-2.5">
              <dt className="w-[40%] text-[11.5px] font-bold text-ink-muted">المفتاح</dt>
              <dd className="flex-1 text-[11.5px] font-extrabold text-ink-title">
                المفتاح العام (anon) فقط — لا يوضع مفتاح service_role في المتصفح أبدًا.
              </dd>
            </div>
            <div className="flex gap-3 py-2.5">
              <dt className="w-[40%] text-[11.5px] font-bold text-ink-muted">الجداول المسجّلة</dt>
              <dd className="flex-1 text-[11.5px] font-extrabold text-ink-title">
                {TABLES.length} جدولًا
              </dd>
            </div>
          </dl>
        </Card>

        <Card title="ما تراه اللوحة وما لا تراه">
          <ul className="space-y-3 text-[12px] font-semibold leading-relaxed text-ink-body">
            <li className="flex gap-2">
              <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-brand" />
              <span>
                <strong className="font-black text-ink-title">الأفراد والجهات</strong> و
                <strong className="font-black text-ink-title">التنبيهات</strong> محفوظة على جهاز
                المستخدم في SharedPreferences، لا في قاعدة البيانات — فلا تظهر هنا حتى تُنقل إلى
                Supabase.
              </span>
            </li>
            <li className="flex gap-2">
              <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-brand" />
              <span>
                مرفقات وحدة الأفراد ملفات محلية داخل مجلد التطبيق، فلا يمكن فتحها من المتصفح.
              </span>
            </li>
            <li className="flex gap-2">
              <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-gold" />
              <span>
                التطبيق يدخل بحساب واحد مشترك، فكل السجلات تحمل نفس user_id. قسم
                «المستخدمون» لا يصير ذا معنى إلا بعد فصل الحسابات وتفعيل RLS لكل مستخدم.
              </span>
            </li>
          </ul>
        </Card>
      </div>
    </>
  )
}
