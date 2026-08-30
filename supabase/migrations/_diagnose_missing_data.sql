-- ============================================================
-- تشخيص: لماذا لا تظهر البيانات المحفوظة؟
-- ============================================================
-- شغّل الأقسام الثلاثة بالترتيب في Supabase ← SQL Editor، وانسخ لي النتائج.
-- لا يعدّل هذا الملف أي بيانات — قراءة فقط.
--
-- البيانات لا تُحذف من قاعدة البيانات إلا بأمر حذف صريح. اختفاؤها من
-- التطبيق يعني غالبًا أحد ثلاثة أسباب:
--   (أ) الصفوف موجودة لكنها مملوكة لمعرّف مستخدم آخر (user_id).
--   (ب) سياسات الحماية (RLS) صارت مفعّلة على جدول كانت مغلقة عليه.
--   (ج) الصفوف لم تُحفظ أصلًا.
-- الأقسام أدناه تفصل بين الثلاثة قطعًا.


-- ============================================================
-- 1) هل الصفوف موجودة أصلًا؟ وكم عددها؟
-- ============================================================
-- تجاوز RLS: هذا الاستعلام يعمل بصلاحية مالك المشروع فيرى كل الصفوف.

select 'project_assets'            as "الجدول", count(*) as "عدد الصفوف" from public.project_assets
union all select 'personal_entries',        count(*) from public.personal_entries
union all select 'shared_entries',          count(*) from public.shared_entries
union all select 'project_asset_entries',   count(*) from public.project_asset_entries
union all select 'property_unit_contracts', count(*) from public.property_unit_contracts
union all select 'wallets',                 count(*) from public.wallets
union all select 'delegations',             count(*) from public.delegations
union all select 'document_records',        count(*) from public.document_records
order by 1;


-- ============================================================
-- 2) لمن تعود الصفوف؟ ومن هو حساب التطبيق؟
-- ============================================================
-- العمود "حساب التطبيق؟" يجب أن يكون true أمام الصف صاحب الأرقام.
-- إن كانت الأرقام أمام صف آخر (حساب مجهول قديم) فالسبب هو (أ):
-- شغّل بعدها ملف _recover_old_data.sql لنقل الملكية.

select
  u.id                                  as "معرّف المستخدم",
  coalesce(u.email, '(مجهول)')          as "البريد",
  (u.email = 'app@fundly.local')        as "حساب التطبيق؟",
  u.created_at                          as "تاريخ الإنشاء",
  (select count(*) from public.project_assets   t where t.user_id = u.id) as "العقارات",
  (select count(*) from public.personal_entries t where t.user_id = u.id) as "الشخصية",
  (select count(*) from public.shared_entries   t where t.user_id = u.id) as "المشتركة",
  (select count(*) from public.wallets          t where t.user_id = u.id) as "المحافظ"
from auth.users u
order by u.created_at;


-- ============================================================
-- 3) حالة سياسات الحماية (RLS) لكل جدول
-- ============================================================
-- إن ظهر جدول بـ RLS = true وكانت صفوفه مملوكة لمعرّف غير حساب التطبيق،
-- فهذا هو السبب (ب): البيانات موجودة لكن السياسة تحجبها عن التطبيق.

select
  c.relname                       as "الجدول",
  c.relrowsecurity                as "RLS مفعّل",
  (select count(*) from pg_policies p
     where p.schemaname = 'public' and p.tablename = c.relname) as "عدد السياسات"
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in (
    'project_assets','project_asset_entries','personal_entries','shared_entries',
    'property_unit_contracts','property_unit_payments','property_unit_transactions',
    'wallets','wallet_transactions','delegations','document_records'
  )
order by c.relname;
