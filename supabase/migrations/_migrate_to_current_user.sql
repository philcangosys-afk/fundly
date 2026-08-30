-- ============================================================
-- نقل البيانات من حساب fundly.app.2026@gmail.com إلى الحساب المجهول الحالي
-- ============================================================

-- الخطوة 1️⃣: معرفة معرّف المستخدم الحالي (المجهول)
-- افتح التطبيق → "حالة البيانات" → انسخ المعرّف الظاهر
-- ثم ضعه في المتغير أدناه

do $$
declare
  -- ⬇️ ضع معرّف المستخدم الحالي هنا (من شاشة "حالة البيانات" في التطبيق)
  current_user_id uuid := 'PASTE_YOUR_CURRENT_USER_ID_HERE';
  
  old_user_id uuid;
  moved bigint;
  total bigint := 0;
  t text;
begin
  -- الحصول على معرّف الحساب القديم
  select id into old_user_id
  from auth.users
  where email = 'fundly.app.2026@gmail.com';
  
  if old_user_id is null then
    raise exception '❌ الحساب القديم fundly.app.2026@gmail.com غير موجود!';
  end if;
  
  if current_user_id::text = 'PASTE_YOUR_CURRENT_USER_ID_HERE' then
    raise exception '❌ يجب تحديث current_user_id أولاً! افتح التطبيق → حالة البيانات → انسخ المعرّف';
  end if;
  
  raise notice '========================================';
  raise notice 'نقل البيانات';
  raise notice 'من الحساب القديم: % (fundly.app.2026@gmail.com)', old_user_id;
  raise notice 'إلى الحساب الحالي: % (مجهول)', current_user_id;
  raise notice '========================================';
  
  -- نقل البيانات من كل جدول
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
    -- تخطي الجداول غير الموجودة
    if to_regclass('public.' || t) is null then
      continue;
    end if;

    -- نقل البيانات
    execute format('update public.%I set user_id = $1 where user_id = $2', t)
      using current_user_id, old_user_id;
    get diagnostics moved = row_count;
    
    if moved > 0 then
      total := total + moved;
      raise notice '  ✓ % : % صف', t, moved;
    end if;
  end loop;

  raise notice '';
  raise notice '========================================';
  raise notice '✓✓✓ اكتمل النقل بنجاح ✓✓✓';
  raise notice 'إجمالي الصفوف المنقولة: %', total;
  raise notice '========================================';
  
  if total = 0 then
    raise warning 'لم يُنقل أي صف! تحقق من المعرفات';
  end if;
end $$;

-- ============================================================
-- التحقق
-- ============================================================

-- عرض توزيع البيانات حسب المستخدمين
select
  u.id,
  coalesce(u.email, '(مجهول)') as "البريد",
  u.is_anonymous as "مجهول؟",
  (select count(*) from public.project_assets where user_id = u.id) as "عقارات",
  (select count(*) from public.personal_entries where user_id = u.id) as "التزامات شخصية",
  (select count(*) from public.shared_entries where user_id = u.id) as "التزامات مشتركة",
  (select count(*) from public.wallets where user_id = u.id) as "محافظ"
from auth.users u
order by u.created_at desc
limit 10;
