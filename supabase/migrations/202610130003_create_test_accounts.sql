-- ============================================================
-- fundly — الحسابان التجريبيان
-- ============================================================
-- شغّله بعد 202610130002. آمن لإعادة التشغيل: الحساب الموجود تُعاد
-- كلمة مروره فقط.
--
--   admin@abdol.com  /  abdol@90
--   admin@zain.com   /  zain@90
--
-- قبل النشر في المتاجر شغّل _delete_test_accounts_before_release.sql
-- ============================================================

create or replace function public._fundly_create_test_user(
  p_email text,
  p_password text,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  uid uuid;
  mail text := lower(trim(p_email));
begin
  select id into uid from auth.users where email = mail;
  if uid is not null then
    update auth.users
    set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = uid;
  else
    uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', uid,
      'authenticated', 'authenticated', mail,
      extensions.crypt(p_password, extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('name', p_name),
      now(), now(),
      '', '', '', ''
    );
    insert into auth.identities (
      user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      uid, uid::text,
      jsonb_build_object('sub', uid::text, 'email', mail, 'email_verified', true),
      'email', now(), now(), now()
    );
  end if;
  update public.profiles
  set display_name = p_name
  where id = uid and display_name = '';
  return uid;
end $$;

select public._fundly_create_test_user('admin@abdol.com', 'abdol@90', 'عبدالعزيز');
select public._fundly_create_test_user('admin@zain.com', 'zain@90', 'زين');

drop function public._fundly_create_test_user(text, text, text);

-- الرقم التعريفي لكل حساب:
select u.email, p.fnd_id, p.display_name
from auth.users u
join public.profiles p on p.id = u.id
order by u.email;
