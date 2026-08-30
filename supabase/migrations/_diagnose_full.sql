-- ============================================================
-- تشخيص شامل: لماذا التطبيق فارغ؟
-- ============================================================

-- 1️⃣ التحقق من حساب app@fundly.local
select 
  '1. حساب app@fundly.local' as "الفحص",
  email,
  id as "UUID",
  email_confirmed_at as "مفعّل؟",
  last_sign_in_at as "آخر دخول",
  created_at
from auth.users
where email = 'app@fundly.local';

-- 2️⃣ عدد البيانات الكلي في كل جدول (بدون RLS)
select 
  '2. إجمالي البيانات' as "الفحص",
  'personal_entries' as "الجدول",
  count(*) as "العدد"
from personal_entries
union all
select 
  '2. إجمالي البيانات',
  'project_assets',
  count(*)
from project_assets
union all
select 
  '2. إجمالي البيانات',
  'shared_entries',
  count(*)
from shared_entries;

-- 3️⃣ توزيع البيانات حسب user_id
select 
  '3. توزيع البيانات' as "الفحص",
  coalesce(u.email, '(مجهول)') as "الحساب",
  (select count(*) from personal_entries e where e.user_id = u.id) as "شخصية",
  (select count(*) from project_assets a where a.user_id = u.id) as "عقارات",
  (select count(*) from shared_entries s where s.user_id = u.id) as "مشتركة"
from auth.users u
where (select count(*) from personal_entries e where e.user_id = u.id) > 0
   or (select count(*) from project_assets a where a.user_id = u.id) > 0
   or (select count(*) from shared_entries s where s.user_id = u.id) > 0
order by u.created_at;

-- 4️⃣ اختبار سياسات RLS: هل يمكن القراءة؟
-- (هذا يُحاكي ما يحدث عندما يتصل التطبيق)
do $$
declare
  app_user_id uuid;
  visible_count int;
begin
  -- الحصول على UUID لحساب app@fundly.local
  select id into app_user_id
  from auth.users
  where email = 'app@fundly.local';
  
  if app_user_id is null then
    raise exception '❌ حساب app@fundly.local غير موجود!';
  end if;
  
  -- محاولة قراءة البيانات (مع RLS)
  select count(*) into visible_count
  from personal_entries
  where user_id = app_user_id;
  
  raise notice '4️⃣ اختبار RLS: الصفوف المرئية لـ app@fundly.local: %', visible_count;
  
  if visible_count = 0 then
    raise warning '⚠️ لا توجد بيانات مرئية! المشكلة في RLS أو البيانات ليست في هذا الحساب';
  else
    raise notice '✅ البيانات مرئية! المشكلة في التطبيق نفسه';
  end if;
end $$;

-- 5️⃣ التحقق من صحة كلمة المرور
-- (لا يمكن اختبار كلمة المرور مباشرة من SQL، لكن يمكن التحقق من الحساب)
select 
  '5. حالة الحساب' as "الفحص",
  case 
    when email_confirmed_at is null then '❌ الحساب غير مفعّل'
    when banned_until is not null then '❌ الحساب محظور'
    else '✅ الحساب جاهز للاستخدام'
  end as "الحالة"
from auth.users
where email = 'app@fundly.local';
