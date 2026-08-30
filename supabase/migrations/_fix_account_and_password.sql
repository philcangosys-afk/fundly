-- ============================================================
-- إصلاح حساب fundly.app.2026@gmail.com وتحديث كلمة المرور
-- ============================================================

-- 1. التحقق من حالة الحساب الحالية
select 
  id,
  email,
  email_confirmed_at is not null as "مفعّل؟",
  created_at,
  last_sign_in_at,
  confirmation_token,
  aud,
  role
from auth.users
where email = 'fundly.app.2026@gmail.com';

-- 2. تحديث الحساب للتأكد من تفعيله بالكامل
update auth.users
set 
  email_confirmed_at = coalesce(email_confirmed_at, now()),
  confirmation_token = '',
  aud = 'authenticated',
  role = 'authenticated',
  encrypted_password = crypt('Fundly-Shared-2026!', gen_salt('bf')),
  updated_at = now()
where email = 'fundly.app.2026@gmail.com';

-- 3. التحقق من التحديث
select 
  id,
  email,
  email_confirmed_at is not null as "مفعّل؟",
  confirmation_token = '' as "رمز التأكيد فارغ؟",
  aud = 'authenticated' as "Aud صحيح؟",
  role = 'authenticated' as "Role صحيح؟",
  created_at,
  updated_at
from auth.users
where email = 'fundly.app.2026@gmail.com';

-- ============================================================
-- اختبار تسجيل الدخول (اختياري)
-- ============================================================
-- يمكنك اختبار تسجيل الدخول من Supabase Dashboard:
-- 1. اذهب إلى Authentication → Users
-- 2. ابحث عن fundly.app.2026@gmail.com
-- 3. تأكد من أن:
--    - Email Confirmed: Yes
--    - Last Sign In: (قد يكون فارغاً قبل أول دخول)
-- ============================================================
