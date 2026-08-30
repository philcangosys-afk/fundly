-- ============================================================
-- نقل جميع البيانات إلى الحساب المجهول الحالي
-- ============================================================
-- المعرّف الحالي: e1d09dfc-a0ed-4b9c-b1d5-f01b4df8959b
-- ============================================================

do $$
declare
  current_user_id uuid := 'e1d09dfc-a0ed-4b9c-b1d5-f01b4df8959b';
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
  
  raise notice '========================================';
  raise notice 'نقل البيانات';
  raise notice 'من: % (fundly.app.2026@gmail.com)', old_user_id;
  raise notice 'إلى: % (مجهول)', current_user_id;
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
    if to_regclass('public.' || t) is null then
      continue;
    end if;

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
end $$;

-- ============================================================
-- التحقق من النقل
-- ============================================================

select
  u.id,
  coalesce(u.email, '(مجهول)') as "الحساب",
  u.is_anonymous as "مجهول؟",
  (select count(*) from public.project_assets where user_id = u.id) as "عقارات",
  (select count(*) from public.personal_entries where user_id = u.id) as "التزامات شخصية",
  (select count(*) from public.shared_entries where user_id = u.id) as "التزامات مشتركة",
  (select count(*) from public.wallets where user_id = u.id) as "محافظ"
from auth.users u
where u.id = 'e1d09dfc-a0ed-4b9c-b1d5-f01b4df8959b'
   or u.email = 'fundly.app.2026@gmail.com'
order by u.created_at desc;

-- ============================================================
-- ✅ بعد التنفيذ:
-- 1. يجب أن ترى الحساب المجهول يحتوي على جميع البيانات
-- 2. الحساب القديم (fundly.app.2026@gmail.com) سيصبح بأصفار
-- 3. أغلق التطبيق وأعد فتحه
-- 4. يجب أن تظهر جميع البيانات القديمة!
-- ============================================================
