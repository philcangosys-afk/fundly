-- ============================================================
-- نقل جميع البيانات من الحسابات المجهولة إلى app@fundly.local
-- ============================================================
-- هذا السكريبت خاص بحالتك ويجمع بيانات كل الحسابات المجهولة
-- ============================================================

do $$
declare
  -- معرّف حساب app@fundly.local (من نتائج الاستعلام الأخير)
  new_user uuid := 'd89c29f5-0f42-41ab-91b5-fbde023d683e';
  
  -- قائمة معرّفات الحسابات المجهولة القديمة (كل الصفوف عدا app@fundly.local)
  old_users uuid[] := array[
    '4417bc1e-5df4-4e18-815b-561b0ab5f54d',
    '44d94021-a1bc-4e6f-bb81-ecf32b983fc7',
    '93813d8b-7a3b-4bb2-b443-2bea3f5a4095',
    'b4f72285-5db0-4981-b8bf-11b7185060dd',
    'd4218164-c6dd-435e-9d4d-d7931268a610',
    '3c51de7f-82c6-41f6-815e-2e895f171204',
    '16d6a3d6-9595-477f-b406-d03cbf0c67b7',
    'dc10501b-7ac4-48be-be81-cff89ef0984d',
    '7b7e127f-8332-407d-8cc3-15b96a7ec147',
    -- 'd530d6e4-c947-4c23-a3f3-4dab0dab51d92',  -- UUID خاطئ - عدّله من الصورة
    '87f93844-f3ca-4c8e-b3a5-9b31f58a87a7',
    'f8f3bf91-5d78-480e-90e3-dac1c4d94e4e'
    -- إذا كان هناك المزيد من المعرفات، أضفها هنا
  ];
  
  old_user uuid;
  moved bigint;
  total bigint := 0;
  t text;
begin
  raise notice '========================================';
  raise notice 'بدء نقل البيانات من جميع الحسابات المجهولة...';
  raise notice 'الحساب الهدف: %', new_user;
  raise notice 'عدد الحسابات المصدر: %', array_length(old_users, 1);
  raise notice '========================================';

  -- حلقة لكل حساب مجهول قديم
  foreach old_user in array old_users
  loop
    raise notice '';
    raise notice '→ معالجة الحساب: %', old_user;
    
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
        using new_user, old_user;
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
  raise notice 'إجمالي الصفوف المنقولة: %', total;
  raise notice '========================================';
  
  if total = 0 then
    raise warning 'لم يُنقل أي صف! تحقق من المعرفات';
  end if;
end $$;


-- ============================================================
-- التحقق النهائي
-- ============================================================
-- بعد تنفيذ السكريبت أعلاه، شغّل هذا الاستعلام للتحقق:

select
  coalesce(u.email, '(مجهول)')          as "البريد",
  (u.email = 'app@fundly.local')        as "حساب التطبيق؟",
  u.created_at                          as "تاريخ الإنشاء",
  (select count(*) from public.project_assets   t where t.user_id = u.id) as "عقارات",
  (select count(*) from public.personal_entries t where t.user_id = u.id) as "شخصية",
  (select count(*) from public.shared_entries   t where t.user_id = u.id) as "مشتركة",
  (select count(*) from public.wallets          t where t.user_id = u.id) as "محافظ",
  (select count(*) from public.delegations      t where t.user_id = u.id) as "تفويضات"
from auth.users u
order by u.created_at;

-- يجب أن ترى كل الأرقام الآن أمام صف app@fundly.local
-- والحسابات المجهولة أصبحت بأصفار
