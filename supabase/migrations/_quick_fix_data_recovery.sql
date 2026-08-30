-- ============================================================
-- حل سريع: استرجاع البيانات وإنشاء حساب التطبيق
-- ============================================================
-- نفّذ هذا الملف في Supabase > SQL Editor لحل مشكلة عدم ظهور البيانات
-- القديمة بعد تحديث التطبيق من الدخول المجهول إلى الحساب الثابت.
-- ============================================================

-- ============================================================
-- الخطوة 1: التشخيص السريع
-- ============================================================
-- شغّل هذا القسم أولاً لمعرفة حالة البيانات الحالية

select
  u.id                                  as user_id,
  coalesce(u.email, '(مجهول)')          as email,
  (u.email = 'app@fundly.local')        as is_app_account,
  u.created_at,
  (select count(*) from public.project_assets   t where t.user_id = u.id) as "عقارات",
  (select count(*) from public.personal_entries t where t.user_id = u.id) as "شخصية",
  (select count(*) from public.shared_entries   t where t.user_id = u.id) as "مشتركة",
  (select count(*) from public.wallets          t where t.user_id = u.id) as "محافظ"
from auth.users u
order by u.created_at;

-- انظر النتيجة:
-- إذا لم تجد صفًا بـ is_app_account = true → تحتاج لإنشاء الحساب (الخطوة 2)
-- إذا وجدت بيانات تحت حساب (مجهول) → تحتاج لنقلها (الخطوة 3)


-- ============================================================
-- الخطوة 2: إنشاء حساب التطبيق (إذا لم يكن موجودًا)
-- ============================================================
-- ⚠️ نفّذ هذا القسم فقط إذا لم تجد app@fundly.local في نتائج الخطوة 1
-- بدلاً من تنفيذ هذا السكريبت، افتح:
-- Supabase > Authentication > Users > Add user > Create new user
-- املأ:
--   Email: app@fundly.local
--   Password: Fundly-Shared-2026!
--   ✅ Auto Confirm User (مهم!)


-- ============================================================
-- الخطوة 3: نقل البيانات من الحساب القديم إلى الجديد
-- ============================================================
-- انسخ معرّفَي المستخدمَين من نتيجة الخطوة 1 وضعهما هنا:

do $$
declare
  -- ▼▼▼ عدّل هذين السطرين فقط ▼▼▼
  old_user uuid := '00000000-0000-0000-0000-000000000000';  -- معرّف الحساب المجهول القديم (صاحب البيانات)
  new_user uuid := '11111111-1111-1111-1111-111111111111';  -- معرّف app@fundly.local (الحساب الجديد)
  -- ▲▲▲ عدّل هذين السطرين فقط ▲▲▲
  
  moved bigint;
  total bigint := 0;
  t text;
begin
  -- فحوصات الأمان
  if old_user = new_user then
    raise exception 'خطأ: المعرّفان متطابقان! راجع نتيجة الخطوة 1';
  end if;
  
  if old_user = '00000000-0000-0000-0000-000000000000'::uuid 
     or new_user = '11111111-1111-1111-1111-111111111111'::uuid then
    raise exception 'خطأ: لم تعدّل المعرّفات! انسخهما من نتيجة الخطوة 1';
  end if;
  
  if not exists (select 1 from auth.users where id = new_user) then
    raise exception 'خطأ: الحساب الجديد غير موجود. نفّذ الخطوة 2 أولاً';
  end if;

  raise notice '========================================';
  raise notice 'بدء نقل البيانات...';
  raise notice '========================================';

  -- نقل الملكية في كل الجداول
  foreach t in array array[
    'project_assets',
    'project_asset_entries',
    'property_unit_contracts',
    'property_unit_payments',
    'property_unit_transactions',
    'personal_entries',
    'shared_entries',
    'commitment_appointments',
    'commitment_attachments',
    'commitment_locations',
    'commitment_notes',
    'commitment_payments',
    'commitment_people',
    'wallets',
    'wallet_transactions',
    'delegations',
    'document_records'
  ]
  loop
    if to_regclass('public.' || t) is null then
      raise notice '⊗ تخطّي % (الجدول غير موجود)', t;
      continue;
    end if;

    execute format('update public.%I set user_id = $1 where user_id = $2', t)
      using new_user, old_user;
    get diagnostics moved = row_count;
    total := total + moved;
    
    if moved > 0 then
      raise notice '✓ % : نُقل % صف', t, moved;
    else
      raise notice '○ % : لا توجد صفوف', t;
    end if;
  end loop;

  raise notice '========================================';
  raise notice '✓ اكتمل النقل: % صف إجمالي', total;
  raise notice '========================================';
  
  if total = 0 then
    raise notice 'تنبيه: لم يُنقل أي صف. تحقق من صحة المعرّفات';
  end if;
end $$;


-- ============================================================
-- الخطوة 4: التحقق من نجاح العملية
-- ============================================================
-- أعد تشغيل استعلام الخطوة 1 - يجب أن تكون كل الأرقام الآن
-- أمام app@fundly.local والأصفار أمام الحساب القديم

select
  u.id                                  as user_id,
  coalesce(u.email, '(مجهول)')          as email,
  (u.email = 'app@fundly.local')        as is_app_account,
  u.created_at,
  (select count(*) from public.project_assets   t where t.user_id = u.id) as "عقارات",
  (select count(*) from public.personal_entries t where t.user_id = u.id) as "شخصية",
  (select count(*) from public.shared_entries   t where t.user_id = u.id) as "مشتركة",
  (select count(*) from public.wallets          t where t.user_id = u.id) as "محافظ"
from auth.users u
order by u.created_at;

-- إذا نجحت العملية:
-- 1. أعد فتح التطبيق (أغلقه من الخلفية)
-- 2. افتح شاشة الالتزامات أو العقارات
-- 3. يجب أن تظهر بياناتك القديمة ✓
