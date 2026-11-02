-- ============================================================
-- fundly — التفويض بالرقم التعريفي
-- ============================================================
-- شغّله بعد 202610130004. آمن لإعادة التشغيل.
--
-- 1) التفويض الذي فيه رقم تعريفي للمفوَّض (@fnd:FND-...) يصل إليه طلبًا،
--    ويراه في «تفويضات وصلتني» بنطاقه وصلاحياته ومدته.
-- 2) المفوَّض يقبل أو يرفض فقط (@accept:...) — لا يغيّر النطاق ولا
--    الصلاحيات ولا المدة. ويصل للمالك إشعار بالرد.
-- 3) بعد القبول وأثناء مدة التفويض: يعرض المفوَّض سجلات المالك في النطاق
--    المفوَّض فقط (القسم، والأقسام الفرعية، والعناصر المحددة إن وُجدت).
-- ============================================================

alter table public.delegations
  add column if not exists shared_ids text[] not null default '{}';
create index if not exists delegations_shared_ids_idx
  on public.delegations using gin (shared_ids);

create or replace function public.fundly_delegation_row()
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
  answer text;
begin
  if tg_op = 'UPDATE' then
    if actor is not null and actor <> old.user_id then
      -- المفوَّض: حالة القبول وحدها، وكل ما عداها كما وضعه المالك.
      answer := (
        select p from unnest(new.permissions) as p
        where p like '@accept:%' limit 1
      );
      new := old;
      new.permissions := array(
        select p from unnest(old.permissions) as p
        where p not like '@accept:%'
      ) || case when answer is null then '{}'::text[] else array[answer] end;
      new.updated_at := now();
    end if;
    new.user_id := old.user_id;
  end if;

  select fnd_id into owner_fnd from public.profiles where id = new.user_id;
  new_ids := array(
    select x
    from unnest(public.fundly_extract_ids(to_jsonb(new.permissions))) as x
    where x is distinct from owner_fnd
  );
  new.shared_ids := new_ids;

  if actor is null then
    return new;
  end if;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  -- رد المفوَّض: إشعار للمالك.
  if tg_op = 'UPDATE'
     and actor <> new.user_id
     and answer is not null
     and not (answer = any(old.permissions)) then
    insert into public.fundly_inbox (
      recipient_id, sender_id, sender_name, sender_fnd,
      source, record_id, entry_type, title
    ) values (
      new.user_id, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
      'delegations', new.id,
      case when answer = '@accept:accepted' then 'قبول تفويض' else 'رفض تفويض' end,
      coalesce(new.scope, '')
    );
    return new;
  end if;

  -- مفوَّض جديد: يصله الطلب.
  if tg_op = 'UPDATE' then
    added := array(
      select x from unnest(new_ids) as x
      where not (x = any(coalesce(old.shared_ids, '{}'::text[])))
    );
  else
    added := new_ids;
  end if;
  if coalesce(array_length(added, 1), 0) = 0 then
    return new;
  end if;
  foreach fid in array added loop
    rid := null;
    select id into rid from public.profiles where fnd_id = fid;
    if rid is not null and rid is distinct from actor then
      insert into public.fundly_inbox (
        recipient_id, sender_id, sender_name, sender_fnd,
        source, record_id, entry_type, title
      ) values (
        rid, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
        'delegations', new.id, 'تفويض', coalesce(new.scope, '')
      );
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists fundly_delegation_row on public.delegations;
create trigger fundly_delegation_row
  before insert or update on public.delegations
  for each row execute function public.fundly_delegation_row();

drop policy if exists "Delegate reads delegation" on public.delegations;
drop policy if exists "Delegate answers delegation" on public.delegations;
create policy "Delegate reads delegation"
  on public.delegations for select to authenticated
  using ((select public.fundly_my_fnd()) = any(shared_ids));
create policy "Delegate answers delegation"
  on public.delegations for update to authenticated
  using ((select public.fundly_my_fnd()) = any(shared_ids))
  with check ((select public.fundly_my_fnd()) = any(shared_ids));

-- التفويضات الموجودة (إن وُجدت).
update public.delegations set permissions = permissions;

-- ------------------------------------------------------------
-- سجلات المالك في نطاق التفويض (للعرض فقط)
-- ------------------------------------------------------------
create or replace function public.fundly_delegated_records(p_delegation uuid)
returns table (
  source text,
  id uuid,
  title text,
  kind text,
  amount numeric,
  due text,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  d public.delegations%rowtype;
  me text := public.fundly_my_fnd();
  main text;
  subs text[];
  personal_ids uuid[];
  shared_ids_ uuid[];
  asset_ids uuid[];
  has_targets boolean;
  slugs text[];
  asset_cats text[];
  shared_types text[];
begin
  select * into d from public.delegations where delegations.id = p_delegation;
  if not found or me is null or not (me = any(d.shared_ids)) then
    return;
  end if;
  if not ('@accept:accepted' = any(d.permissions))
     or not ('عرض البيانات' = any(d.permissions))
     or d.is_paused
     or (d.start_date is not null and d.start_date > current_date)
     or (d.end_date is not null and d.end_date < current_date) then
    return;
  end if;

  main := trim(split_part(d.scope, ' — ', 1));
  subs := array(
    select trim(s)
    from unnest(string_to_array(split_part(d.scope, ' — ', 2), '،')) as s
    where trim(s) <> ''
  );

  -- عناصر بعينها: @target:الفرع|النوع|المعرّف|الاسم
  personal_ids := array(
    select split_part(substr(p, 9), '|', 3)::uuid
    from unnest(d.permissions) as p
    where p like '@target:%' and split_part(substr(p, 9), '|', 2) = 'personal'
      and split_part(substr(p, 9), '|', 3) ~ '^[0-9a-f-]{36}$'
  );
  shared_ids_ := array(
    select split_part(substr(p, 9), '|', 3)::uuid
    from unnest(d.permissions) as p
    where p like '@target:%' and split_part(substr(p, 9), '|', 2) = 'shared'
      and split_part(substr(p, 9), '|', 3) ~ '^[0-9a-f-]{36}$'
  );
  asset_ids := array(
    select split_part(split_part(substr(p, 9), '|', 3), '#', 1)::uuid
    from unnest(d.permissions) as p
    where p like '@target:%'
      and split_part(substr(p, 9), '|', 2) in ('asset', 'unit')
      and split_part(split_part(substr(p, 9), '|', 3), '#', 1) ~ '^[0-9a-f-]{36}$'
  );
  has_targets := exists (
    select 1 from unnest(d.permissions) as p where p like '@target:%'
  );

  slugs := array(
    select case s
      when 'مالية' then 'financial'
      when 'مستند' then 'document'
      when 'المتابعة والتخطيط' then 'organization'
      when 'أدوية وبيانات وكلمات سر' then 'medical_accounts'
      when 'نمط الحياة' then 'lifestyle'
      when 'مواقع وأماكن' then 'location'
      when 'عهدة مالية' then 'custody'
      else s end
    from unnest(subs) as s
  );
  asset_cats := array(
    select case s
      when 'العقارات' then 'real_estate'
      when 'الأنشطة التجارية' then 'business'
      when 'المركبات ووسائل النقل' then 'equipment'
      else s end
    from unnest(subs) as s
  );
  shared_types := subs;

  if main in ('كل الأقسام', 'الالتزامات الشخصية') then
    return query
      select 'personal_entries'::text, e.id, e.title, e.entry_type,
             e.amount, coalesce(e.due_date::text, ''), e.status
      from public.personal_entries e
      where e.user_id = d.user_id
        and e.status <> 'محذوف'
        and (
          main = 'كل الأقسام'
          or (has_targets and e.id = any(personal_ids))
          or (not has_targets and (
            cardinality(subs) = 0
            or e.category = any(slugs)
            or ('custody' = any(slugs) and e.entry_type = 'عهدة مالية')
          ))
        )
      order by e.created_at desc
      limit 300;
  end if;

  if main in ('كل الأقسام', 'الالتزامات المشتركة') then
    return query
      select 'shared_entries'::text, e.id, e.title, e.entry_type,
             e.amount, coalesce(e.due_date::text, ''), e.status
      from public.shared_entries e
      where e.user_id = d.user_id
        and e.status <> 'محذوف'
        and (
          main = 'كل الأقسام'
          or (has_targets and e.id = any(shared_ids_))
          or (not has_targets and (
            cardinality(subs) = 0
            or e.entry_type = any(shared_types)
            or (e.entry_type = 'اللقاءات' and 'مشاركات مشتركة' = any(shared_types))
          ))
        )
      order by e.created_at desc
      limit 300;
  end if;

  if main in ('كل الأقسام', 'العقارات والأنشطة والمركبات') then
    return query
      select 'project_assets'::text, a.id, a.title, a.sub_type,
             0::numeric, coalesce(a.end_date::text, ''), a.status
      from public.project_assets a
      where a.user_id = d.user_id
        and a.status <> 'محذوف'
        and (
          main = 'كل الأقسام'
          or (has_targets and a.id = any(asset_ids))
          or (not has_targets and (
            cardinality(subs) = 0 or a.category = any(asset_cats)
          ))
        )
      order by a.created_at desc
      limit 300;
  end if;
end $$;

revoke all on function public.fundly_delegated_records(uuid) from public, anon;
grant execute on function public.fundly_delegated_records(uuid) to authenticated;
