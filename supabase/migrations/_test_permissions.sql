-- ============================================================
-- اختبار نهائي: هل يمكن للتطبيق قراءة البيانات؟
-- ============================================================

-- 1. عرض المستخدم الحالي
select 
  auth.uid() as "user_id الحالي",
  auth.email() as "البريد الإلكتروني";

-- 2. عد البيانات المرئية للمستخدم الحالي
select 
  'personal_entries' as "الجدول",
  count(*) as "الصفوف المرئية"
from personal_entries
where user_id = auth.uid()

union all

select 
  'project_assets',
  count(*)
from project_assets
where user_id = auth.uid()

union all

select 
  'shared_entries',
  count(*)
from shared_entries
where user_id = auth.uid()

union all

select 
  'wallets',
  count(*)
from wallets
where user_id = auth.uid();

-- 3. اختبار الإدراج (insert test)
-- هذا لن يدرج بيانات فعلية، فقط يختبر الصلاحية
do $$
begin
  -- محاولة إنشاء سجل وهمي
  insert into personal_entries (
    user_id,
    title,
    created_at
  ) values (
    auth.uid(),
    'اختبار الصلاحيات',
    now()
  );
  
  -- حذف السجل الوهمي فوراً
  delete from personal_entries 
  where title = 'اختبار الصلاحيات' 
    and user_id = auth.uid();
  
  raise notice '✅ اختبار الإدراج نجح! يمكن للتطبيق الحفظ';
exception when others then
  raise warning '❌ اختبار الإدراج فشل: %', sqlerrm;
end $$;
