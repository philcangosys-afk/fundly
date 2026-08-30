-- ============================================================
-- إنشاء حساب التطبيق app@fundly.local
-- ============================================================
-- نفّذ هذا في Supabase SQL Editor لإنشاء الحساب
-- ============================================================

-- الطريقة 1: باستخدام auth.users مباشرة (يتطلب صلاحيات)
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  recovery_sent_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  confirmation_token,
  email_change,
  email_change_token_new,
  recovery_token
)
select
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'app@fundly.local',
  crypt('Fundly-Shared-2026!', gen_salt('bf')),
  now(),
  now(),
  now(),
  '{"provider":"email","providers":["email"]}',
  '{}',
  now(),
  now(),
  '',
  '',
  '',
  ''
where not exists (
  select 1 from auth.users where email = 'app@fundly.local'
);

-- التحقق من إنشاء الحساب
select 
  id,
  email,
  email_confirmed_at is not null as "مفعّل؟",
  created_at
from auth.users
where email = 'app@fundly.local';


-- ============================================================
-- إذا فشلت الطريقة أعلاه، جرب هذا:
-- ============================================================

-- حذف الحساب القديم إن كان موجوداً (لكن غير مفعّل)
-- delete from auth.users where email = 'app@fundly.local' and email_confirmed_at is null;

-- ثم أنشئ الحساب من Dashboard كما ذكرت في التعليمات
