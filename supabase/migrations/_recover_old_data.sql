-- ============================================================
-- استرجاع البيانات القديمة بعد إعادة تثبيت التطبيق
-- ============================================================
-- التطبيق يسجّل الدخول بحساب مجهول (signInAnonymously)، والهوية مخزَّنة
-- داخل التطبيق نفسه. عند حذف التطبيق تُمحى تلك الهوية ويُنشأ مستخدم مجهول
-- جديد بمعرّف مختلف — فتصبح بياناتك القديمة غير مرئية لأن سياسات الحماية
-- تربط كل صف بـ user_id صاحبه. البيانات لم تُحذف، بل صارت مملوكة لمعرّف آخر.
--
-- شغّل الخطوة (1) أولًا وانظر النتيجة، ثم الخطوة (2).
-- ============================================================


-- ============================================================
-- الخطوة 1 — اعرض كل المستخدمين المجهولين وعدد صفوف كل واحد
-- ============================================================
-- الصف صاحب الأرقام الكبيرة والتاريخ الأقدم هو حسابك القديم.
-- الصف الأحدث (وغالبًا بأصفار) هو حسابك الحالي بعد إعادة التثبيت.

select
  u.id                    as user_id,
  u.created_at            as "تاريخ الإنشاء",
  (select count(*) from public.project_assets           t where t.user_id = u.id) as "العقارات والأنشطة",
  (select count(*) from public.personal_entries         t where t.user_id = u.id) as "الالتزامات الشخصية",
  (select count(*) from public.shared_entries           t where t.user_id = u.id) as "الالتزامات المشتركة",
  (select count(*) from public.property_unit_contracts  t where t.user_id = u.id) as "عقود الوحدات",
  (select count(*) from public.commitment_payments      t where t.user_id = u.id) as "المدفوعات"
from auth.users u
order by u.created_at;


-- ============================================================
-- الخطوة 2 — انقل ملكية البيانات القديمة إلى حسابك الحالي
-- ============================================================
-- انسخ المعرّفين من نتيجة الخطوة (1) وضعهما هنا، ثم شغّل هذا القسم كاملًا.
-- كل شيء داخل معاملة واحدة: إمّا أن ينجح الكل أو لا يتغيّر شيء.

do $$
declare
  -- ▼▼▼ عدّل هذين السطرين فقط ▼▼▼
  old_user uuid := '00000000-0000-0000-0000-000000000000';  -- الحساب القديم (صاحب البيانات)
  new_user uuid := '11111111-1111-1111-1111-111111111111';  -- حسابك الحالي بعد إعادة التثبيت
  -- ▲▲▲ عدّل هذين السطرين فقط ▲▲▲
  moved bigint;
  total bigint := 0;
  t text;
begin
  if old_user = new_user then
    raise exception 'المعرّفان متطابقان — راجع نتيجة الخطوة 1';
  end if;
  if not exists (select 1 from auth.users where id = new_user) then
    raise exception 'الحساب الحالي غير موجود: %', new_user;
  end if;

  -- كل الجداول التي تحمل عمود user_id
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
    'commitment_people'
  ]
  loop
    -- تخطَّ أي جدول غير موجود بدل إيقاف العملية كلها
    if to_regclass('public.' || t) is null then
      raise notice 'تخطّي % (غير موجود)', t;
      continue;
    end if;

    execute format('update public.%I set user_id = $1 where user_id = $2', t)
      using new_user, old_user;
    get diagnostics moved = row_count;
    total := total + moved;
    raise notice '% : % صف', t, moved;
  end loop;

  raise notice '--------------------------------';
  raise notice 'الإجمالي المنقول: % صف', total;
end $$;


-- ============================================================
-- الخطوة 3 — تحقّق
-- ============================================================
-- أعد تشغيل استعلام الخطوة (1): يجب أن تكون كل الأرقام الآن أمام حسابك
-- الحالي، وأصفارًا أمام الحساب القديم. بعدها أعد فتح التطبيق.
