-- ============================================================
-- fundly — حسابات حقيقية منفصلة + الرقم التعريفي + صندوق الطلبات
-- ============================================================
-- شغّله بعد 202610130001 (حذف بيانات التجارب) وقبل 202610130003.
-- آمن لإعادة التشغيل.
--
-- 1) profiles: لكل حساب رقم تعريفي FND-XXXX-XXXX يولّده الخادم عند إنشاء
--    الحساب، ولا يتغيّر ولا يضيع بحذف التطبيق.
-- 2) الدخول بالبريد، أو بالهاتف، أو بالرقم التعريفي + كلمة المرور.
-- 3) كل جدول: صاحب الحساب يرى سجلاته فقط.
-- 4) السجل الذي يُذكر فيه رقم تعريفي لشخص آخر (عهدة، رحلة، مشاركة...)
--    يراه ذلك الشخص ويعدّله، ويصله طلب في صندوقه فورًا.
-- 5) fundly_user_store: نسخة سحابية لبيانات الجهاز (الأفراد، الكلندر،
--    الملاحظات...) حتى تظهر عند الدخول من جوال آخر.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------------------
-- 1) الملف الشخصي والرقم التعريفي
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  fnd_id text not null unique,
  display_name text not null default '',
  phone text not null default '',
  created_at timestamptz not null default now()
);

create or replace function public.fundly_generate_fnd_id()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
  i int;
begin
  loop
    candidate := 'FND-';
    for i in 1..8 loop
      if i = 5 then
        candidate := candidate || '-';
      end if;
      candidate := candidate
        || substr(alphabet, 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (
      select 1 from public.profiles where fnd_id = candidate
    );
  end loop;
  return candidate;
end $$;

create or replace function public.fundly_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, fnd_id, display_name)
  values (
    new.id,
    public.fundly_generate_fnd_id(),
    coalesce(new.raw_user_meta_data ->> 'name', '')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists fundly_on_auth_user_created on auth.users;
create trigger fundly_on_auth_user_created
  after insert on auth.users
  for each row execute function public.fundly_handle_new_user();

-- حسابات موجودة قبل هذا الملف تأخذ رقمها الآن.
insert into public.profiles (id, fnd_id, display_name)
select
  u.id,
  public.fundly_generate_fnd_id(),
  coalesce(u.raw_user_meta_data ->> 'name', '')
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);

alter table public.profiles enable row level security;
drop policy if exists "Profiles: read own" on public.profiles;
drop policy if exists "Profiles: update own" on public.profiles;
create policy "Profiles: read own"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy "Profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- الرقم التعريفي لا يعدّله أحد من التطبيق: الاسم والهاتف فقط.
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, phone) on public.profiles to authenticated;

-- رقمي التعريفي (تستعمله سياسات المشاركة).
create or replace function public.fundly_my_fnd()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select fnd_id from public.profiles where id = auth.uid()
$$;
revoke all on function public.fundly_my_fnd() from public, anon;
grant execute on function public.fundly_my_fnd() to authenticated;

-- ------------------------------------------------------------
-- 2) الدخول بالهاتف أو بالرقم التعريفي: يعيد البريد المرتبط ثم يدخل
--    التطبيق بالبريد وكلمة المرور كالمعتاد.
-- ------------------------------------------------------------
create or replace function public.fundly_login_email(p_identifier text)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v text := upper(trim(coalesce(p_identifier, '')));
  digits text;
  found_email text;
  matches int;
begin
  if v like 'FND-%' then
    select u.email into found_email
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.fnd_id = replace(v, ' ', '');
    return found_email;
  end if;
  digits := regexp_replace(v, '\D', '', 'g');
  if length(digits) < 8 then
    return null;
  end if;
  -- آخر 9 أرقام (رقم الجوال بلا رمز الدولة ولا الصفر).
  select count(*), min(u.email) into matches, found_email
  from public.profiles p
  join auth.users u on u.id = p.id
  where length(regexp_replace(p.phone, '\D', '', 'g')) >= 8
    and right(regexp_replace(p.phone, '\D', '', 'g'), 9) = right(digits, 9);
  if matches = 1 then
    return found_email;
  end if;
  return null;
end $$;
revoke all on function public.fundly_login_email(text) from public;
grant execute on function public.fundly_login_email(text) to anon, authenticated;

-- ------------------------------------------------------------
-- 3) صندوق الطلبات: ما يصلك من حساب آخر (عهدة، دعوة رحلة، مشاركة...)
-- ------------------------------------------------------------
create table if not exists public.fundly_inbox (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  sender_name text not null default '',
  sender_fnd text not null default '',
  source text not null default '',
  record_id uuid,
  entry_type text not null default '',
  title text not null default '',
  status text not null default 'new' check (status in ('new', 'seen')),
  created_at timestamptz not null default now(),
  seen_at timestamptz
);

create index if not exists fundly_inbox_recipient_idx
  on public.fundly_inbox (recipient_id, status, created_at desc);

alter table public.fundly_inbox enable row level security;
drop policy if exists "Inbox: read mine" on public.fundly_inbox;
drop policy if exists "Inbox: mark mine" on public.fundly_inbox;
drop policy if exists "Inbox: delete mine" on public.fundly_inbox;
create policy "Inbox: read mine"
  on public.fundly_inbox for select to authenticated
  using (
    recipient_id = (select auth.uid()) or sender_id = (select auth.uid())
  );
create policy "Inbox: mark mine"
  on public.fundly_inbox for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));
create policy "Inbox: delete mine"
  on public.fundly_inbox for delete to authenticated
  using (recipient_id = (select auth.uid()));

revoke all on public.fundly_inbox from anon, authenticated;
grant select, delete on public.fundly_inbox to authenticated;
grant update (status, seen_at) on public.fundly_inbox to authenticated;

-- ------------------------------------------------------------
-- 4) نسخة سحابية لبيانات الجهاز
-- ------------------------------------------------------------
create table if not exists public.fundly_user_store (
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  key text not null,
  value text not null default '',
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- ------------------------------------------------------------
-- 5) كل جدول: صاحب الحساب فقط (تُحذف السياسات القديمة كلها، ومنها ما
--    كان يفتح البيانات للحساب المشترك).
-- ------------------------------------------------------------
do $$
declare
  t text;
  p record;
begin
  foreach t in array array[
    'personal_entries',
    'shared_entries',
    'project_assets',
    'project_asset_entries',
    'commitment_payments',
    'commitment_attachments',
    'commitment_appointments',
    'commitment_notes',
    'commitment_people',
    'commitment_locations',
    'property_unit_contracts',
    'property_unit_payments',
    'property_unit_transactions',
    'wallets',
    'wallet_transactions',
    'delegations',
    'document_records',
    'fundly_user_store'
  ]
  loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;
    for p in
      select policyname from pg_policies
      where schemaname = 'public' and tablename = t
    loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "Owner full access" on public.%I for all to authenticated '
      'using (user_id = (select auth.uid())) '
      'with check (user_id = (select auth.uid()))',
      t
    );
    execute format('revoke all on public.%I from anon', t);
    execute format(
      'grant select, insert, update, delete on public.%I to authenticated',
      t
    );
  end loop;
end $$;

-- ------------------------------------------------------------
-- 6) المشاركة بين الحسابات بالرقم التعريفي
-- ------------------------------------------------------------
-- كل الأرقام التعريفية المذكورة في تفاصيل السجل.
create or replace function public.fundly_extract_ids(p_details jsonb)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(distinct s.x), '{}'::text[])
  from (
    select (regexp_matches(
      coalesce(p_details::text, ''),
      'FND-[A-Z2-9]{4}-[A-Z2-9]{4}',
      'g'
    ))[1] as x
  ) s
$$;

alter table public.personal_entries
  add column if not exists shared_ids text[] not null default '{}';
alter table public.shared_entries
  add column if not exists shared_ids text[] not null default '{}';

create index if not exists personal_entries_shared_ids_idx
  on public.personal_entries using gin (shared_ids);
create index if not exists shared_entries_shared_ids_idx
  on public.shared_entries using gin (shared_ids);

-- قبل كل حفظ: يُحسب من يشارك السجل، ويُرسل طلب لكل رقم جديد أُضيف.
create or replace function public.fundly_share_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_fnd text;
  actor uuid := auth.uid();
  actor_name text;
  actor_fnd text;
  new_ids text[];
  added text[];
  fid text;
  rid uuid;
begin
  if tg_op = 'UPDATE' then
    -- الشريك يعدّل السجل لكنه لا يصير مالكه.
    new.user_id := old.user_id;
  end if;

  select fnd_id into owner_fnd from public.profiles where id = new.user_id;

  new_ids := array(
    select x
    from unnest(public.fundly_extract_ids(new.details)) as x
    where x is distinct from owner_fnd
  );
  new.shared_ids := new_ids;

  if tg_op = 'UPDATE' then
    added := array(
      select x
      from unnest(new_ids) as x
      where not (x = any(coalesce(old.shared_ids, '{}'::text[])))
    );
  else
    added := new_ids;
  end if;

  -- لا طلبات بلا مُرسِل (تحديث من لوحة Supabase مثلًا).
  if actor is null or coalesce(array_length(added, 1), 0) = 0 then
    return new;
  end if;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  foreach fid in array added loop
    rid := null;
    select id into rid from public.profiles where fnd_id = fid;
    if rid is not null and rid is distinct from actor then
      insert into public.fundly_inbox (
        recipient_id, sender_id, sender_name, sender_fnd,
        source, record_id, entry_type, title
      ) values (
        rid, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
        tg_table_name, new.id, coalesce(new.entry_type, ''),
        coalesce(new.title, '')
      );
    end if;
  end loop;

  return new;
end $$;

drop trigger if exists fundly_share_row on public.personal_entries;
create trigger fundly_share_row
  before insert or update on public.personal_entries
  for each row execute function public.fundly_share_row();

drop trigger if exists fundly_share_row on public.shared_entries;
create trigger fundly_share_row
  before insert or update on public.shared_entries
  for each row execute function public.fundly_share_row();

-- الطرف الآخر يقرأ السجل المذكور فيه رقمه ويعدّله (القبول، الصرف من
-- العهدة، مصروفات الرحلة...). الحذف لصاحب السجل وحده.
create policy "Counterpart read shared rows"
  on public.personal_entries for select to authenticated
  using ((select public.fundly_my_fnd()) = any(shared_ids));
create policy "Counterpart update shared rows"
  on public.personal_entries for update to authenticated
  using ((select public.fundly_my_fnd()) = any(shared_ids))
  with check ((select public.fundly_my_fnd()) = any(shared_ids));

create policy "Counterpart read shared rows"
  on public.shared_entries for select to authenticated
  using ((select public.fundly_my_fnd()) = any(shared_ids));
create policy "Counterpart update shared rows"
  on public.shared_entries for update to authenticated
  using ((select public.fundly_my_fnd()) = any(shared_ids))
  with check ((select public.fundly_my_fnd()) = any(shared_ids));

-- السجلات الموجودة (إن وُجدت) تُحسب مشاركتها الآن.
update public.personal_entries set details = details;
update public.shared_entries set details = details;
