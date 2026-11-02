-- ============================================================
-- fundly — حذف كل بيانات التجارب نهائيًا
-- ============================================================
-- شغّله أولًا في Supabase ← SQL Editor، ثم ملف 202610130002 ثم 202610130003.
--
-- يحذف:
--   1) كل السجلات في كل جداول التطبيق.
--   2) كل الملفات المرفوعة في مخازن التطبيق (إن سمح Supabase بالحذف من SQL).
--   3) كل حسابات الدخول القديمة، ومنها الحساب المشترك
--      fundly.app.2026@gmail.com.
--
-- تحذير: لا رجعة فيه. لا تشغّله بعد بدء الاستخدام الحقيقي.
-- ============================================================

-- 1) سجلات الجداول.
do $$
declare
  t text;
begin
  foreach t in array array[
    'fundly_inbox',
    'fundly_user_store',
    'commitment_payments',
    'commitment_attachments',
    'commitment_appointments',
    'commitment_notes',
    'commitment_people',
    'commitment_locations',
    'property_unit_payments',
    'property_unit_contracts',
    'property_unit_transactions',
    'project_asset_entries',
    'project_assets',
    'wallet_transactions',
    'wallets',
    'document_records',
    'delegations',
    'shared_entries',
    'personal_entries',
    'profiles'
  ]
  loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I', t);
      raise notice 'emptied public.%', t;
    end if;
  end loop;
end $$;

-- 2) الملفات المرفوعة. إصدارات Supabase الحديثة تمنع الحذف المباشر من
--    storage.objects؛ عندها تظهر رسالة فقط، وتُفرَّغ المخازن يدويًا من
--    Storage ← اختيار المخزن ← تحديد الكل ← Delete.
do $$
begin
  delete from storage.objects
  where bucket_id in (
    'personal-entry-attachments',
    'shared-entry-attachments',
    'project-asset-attachments',
    'commitment-attachments',
    'fundly-files'
  );
  raise notice 'storage objects deleted';
exception
  when others then
    raise notice 'storage not emptied from SQL (%). Empty the buckets from the Storage page.', sqlerrm;
end $$;

-- 3) كل حسابات الدخول القديمة (بياناتها المرتبطة تُحذف معها تلقائيًا).
delete from auth.users;
