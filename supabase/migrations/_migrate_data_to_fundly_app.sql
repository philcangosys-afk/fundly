-- ============================================================
-- نقل جميع البيانات إلى حساب fundly.app.2026@gmail.com
-- ============================================================
-- يكتشف تلقائياً كل الحسابات المجهولة والقديمة وينقل بياناتها
-- إلى حساب التطبيق الموحد
-- ============================================================

do $$
declare
  -- معرّف حساب fundly.app.2026@gmail.com (يُكتشف تلقائياً)
  target_user uuid;
  
  source_user record;
  moved bigint;
  total bigint := 0;
  t text;
  user_count int := 0;
begin
  -- البحث عن حساب fundly.app.2026@gmail.com
  select id into target_user
  from auth.users
  where email = 'fundly.app.2026@gmail.com';
  
  if target_user is null then
    raise exception '❌ الحساب fundly.app.2026@gmail.com غير موجود! أنشئه أولاً من Dashboard';
  end if;
  
  raise notice '========================================';
  raise notice 'نقل البيانات من جميع الحسابات الأخرى';
  raise notice 'الحساب الهدف: % (fundly.app.2026@gmail.com)', target_user;
  raise notice '========================================';

  -- حلقة على كل الحسابات الأخرى (كل الحسابات عدا الحساب الهدف)
  for source_user in (
    select id, coalesce(email, '(مجهول)') as email
    from auth.users
    where id != target_user
    order by created_at
  )
  loop
    user_count := user_count + 1;
    raise notice '';
    raise notice '→ معالجة الحساب [%]: % (%)', user_count, source_user.email, source_user.id;
    
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
        using target_user, source_user.id;
      get diagnostics moved = row_count;
      
      if moved > 0 then
        total := total + moved;
        raise notice '  ✓ % : % صف', t, moved;
      end if;
    end loop;
  end loop;

  raise notice '';
  raise notice '========================================';
  raise notice '✓✓✓ اكتمل النقل بنجاح ✓✓✓';
  raise notice 'عدد الحسابات المعالجة: %', user_count;
  raise notice 'إجمالي الصفوف المنقولة: %', total;
  raise notice '========================================';
  
  if total = 0 then
    raise warning 'لم يُنقل أي صف! جميع البيانات موجودة في الحساب الهدف مسبقاً';
  end if;
end $$;


-- ============================================================
-- التحقق النهائي
-- ============================================================
-- بعد تنفيذ السكريبت أعلاه، شغّل هذا الاستعلام للتحقق:

select
  coalesce(u.email, '(مجهول)')          as "البريد",
  (u.email = 'fundly.app.2026@gmail.com') as "حساب التطبيق؟",
  u.created_at                          as "تاريخ الإنشاء",
  (select count(*) from public.project_assets   t where t.user_id = u.id) as "عقارات",
  (select count(*) from public.personal_entries t where t.user_id = u.id) as "شخصية",
  (select count(*) from public.shared_entries   t where t.user_id = u.id) as "مشتركة",
  (select count(*) from public.wallets          t where t.user_id = u.id) as "محافظ",
  (select count(*) from public.delegations      t where t.user_id = u.id) as "تفويضات"
from auth.users u
order by u.created_at;

-- يجب أن ترى كل الأرقام الآن أمام صف fundly.app.2026@gmail.com
-- والحسابات الأخرى أصبحت بأصفار
