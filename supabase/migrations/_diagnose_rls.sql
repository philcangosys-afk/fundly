-- ============================================================
-- تشخيص سياسات الأمان (RLS) على الجداول
-- ============================================================

-- 1. التحقق من حالة RLS على كل جدول
select 
  schemaname as "المخطط",
  tablename as "الجدول",
  rowsecurity as "RLS مفعّل؟"
from pg_tables
where schemaname = 'public'
  and tablename in (
    'project_assets',
    'personal_entries', 
    'shared_entries',
    'wallets',
    'delegations'
  )
order by tablename;

-- 2. عرض جميع السياسات الموجودة
select 
  schemaname as "المخطط",
  tablename as "الجدول",
  policyname as "اسم السياسة",
  cmd as "العملية",
  qual as "الشرط"
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- 3. اختبار بسيط: هل يمكن قراءة البيانات؟
-- (هذا سيفشل إذا كانت RLS تمنع القراءة)
select 
  'personal_entries' as "جدول",
  count(*) as "عدد الصفوف المرئية"
from personal_entries
union all
select 
  'project_assets',
  count(*)
from project_assets
union all
select 
  'shared_entries',
  count(*)
from shared_entries;
