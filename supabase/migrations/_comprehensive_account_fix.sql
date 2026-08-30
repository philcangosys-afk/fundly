-- ============================================================
-- تشخيص شامل وإصلاح مشكلة تسجيل الدخول
-- ============================================================

do $$
declare
  target_user_id uuid;
  deleted_sessions int;
  deleted_tokens int;
begin
  -- الحصول على معرّف الحساب
  select id into target_user_id
  from auth.users
  where email = 'fundly.app.2026@gmail.com';
  
  if target_user_id is null then
    raise exception '❌ الحساب fundly.app.2026@gmail.com غير موجود!';
  end if;
  
  raise notice '📋 معرّف الحساب: %', target_user_id;
  
  -- حذف الجلسات القديمة
  delete from auth.sessions where user_id = target_user_id;
  get diagnostics deleted_sessions = row_count;
  raise notice '🗑️ حُذفت % جلسة قديمة', deleted_sessions;
  
  -- حذف refresh tokens القديمة (user_id في هذا الجدول varchar)
  delete from auth.refresh_tokens where user_id = target_user_id::text;
  get diagnostics deleted_tokens = row_count;
  raise notice '🗑️ حُذفت % refresh token قديم', deleted_tokens;
  
  -- إعادة تعيين الحساب بالكامل
  update auth.users
  set 
    -- التأكد من التفعيل
    email_confirmed_at = now(),
    confirmation_token = '',
    confirmation_sent_at = null,
    
    -- إزالة أي حظر
    banned_until = null,
    deleted_at = null,
    
    -- الصلاحيات الصحيحة
    aud = 'authenticated',
    role = 'authenticated',
    
    -- تحديث كلمة المرور
    encrypted_password = crypt('Fundly-Shared-2026!', gen_salt('bf')),
    
    -- تحديث الوقت
    updated_at = now(),
    
    -- metadata
    raw_app_meta_data = jsonb_build_object(
      'provider', 'email',
      'providers', array['email']::text[]
    ),
    raw_user_meta_data = '{}'::jsonb
  where id = target_user_id;
  
  raise notice '✅ تم تحديث الحساب بنجاح';
end $$;

-- ============================================================
-- التحقق النهائي
-- ============================================================

-- 1️⃣ حالة الحساب
select 
  '✅ الحساب جاهز للاستخدام' as "الحالة",
  email,
  id,
  email_confirmed_at is not null as "مفعّل",
  aud,
  role
from auth.users
where email = 'fundly.app.2026@gmail.com';

-- 2️⃣ عدد البيانات المرتبطة
select 
  u.email,
  (select count(*) from public.project_assets where user_id = u.id) as "عقارات",
  (select count(*) from public.personal_entries where user_id = u.id) as "التزامات شخصية",
  (select count(*) from public.shared_entries where user_id = u.id) as "التزامات مشتركة",
  (select count(*) from public.wallets where user_id = u.id) as "محافظ"
from auth.users u
where email = 'fundly.app.2026@gmail.com';

-- ============================================================
-- ✅ بعد تنفيذ هذا السكريبت:
-- 1. تحقق من أن الحالة = "الحساب جاهز للاستخدام"
-- 2. سترى رسائل النجاح في الـ Messages
-- 3. أعد تشغيل التطبيق
-- 4. انتظر 30 ثانية وراقب شاشة "حالة البيانات"
-- 
-- إذا استمرت المشكلة، تحقق من:
-- - Supabase Dashboard → Configuration → Authentication
-- - تأكد أن "Enable email confirmations" مُعطّل (OFF)
-- - تأكد أن "Enable custom access token hook" مُعطّل (OFF)
-- ============================================================
