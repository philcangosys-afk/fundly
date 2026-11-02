-- ============================================================
-- fundly — إشعار وسجل لكل تغيير في التفويض (من الطرفين)
-- ============================================================
-- شغّله بعد 202610270002. آمن لإعادة التشغيل.
--
-- • المالك يعدّل التفويض (الصلاحيات، المدة، النطاق، الإيقاف، التمديد،
--   الإلغاء الفوري): يصل للمفوَّض إشعار بما تغيّر — نص آخر حدث في سجل
--   التفويض (@log) — للاطلاع.
-- • المالك يحذف التفويض: يصل للمفوَّض إشعار «حذف التفويض».
-- • المفوَّض يقبل أو يرفض أو ينسحب أو يعود: يُكتب في سجل التفويض باسمه
--   وتاريخه (والإشعار للمالك كما كان).
-- ============================================================

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
  added text[] := '{}';
  fid text;
  rid uuid;
  answer text;
  old_answer text;
  log_text text;
  ts text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
begin
  if actor is not null then
    select display_name, fnd_id into actor_name, actor_fnd
    from public.profiles where id = actor;
  end if;

  if tg_op = 'UPDATE' then
    if actor is not null and actor <> old.user_id then
      -- المفوَّض: حالة القبول وحدها، وكل ما عداها كما وضعه المالك.
      answer := (
        select p from unnest(new.permissions) as p
        where p like '@accept:%' limit 1
      );
      old_answer := (
        select p from unnest(old.permissions) as p
        where p like '@accept:%' limit 1
      );
      new := old;
      new.permissions := array(
        select p from unnest(old.permissions) as p
        where p not like '@accept:%'
      ) || case when answer is null then '{}'::text[] else array[answer] end;
      -- سجل التفويض: رد المفوَّض باسمه وتاريخه.
      if answer is not null and answer is distinct from old_answer then
        log_text := coalesce(nullif(actor_name, ''), actor_fnd, 'المفوَّض')
          || ' ' || case answer
            when '@accept:accepted' then
              case when old_answer = '@accept:withdrawn'
                then 'عاد إلى التفويض' else 'قبِل التفويض' end
            when '@accept:withdrawn' then 'انسحب من التفويض'
            else 'رفض التفويض' end;
        new.permissions := new.permissions
          || array['@log:' || ts || '|' || log_text];
      end if;
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

  -- رد المفوَّض: إشعار للمالك (قبول، رفض، انسحاب).
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
      case answer
        when '@accept:accepted' then 'قبول تفويض'
        when '@accept:withdrawn' then 'انسحاب من تفويض'
        else 'رفض تفويض' end,
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
  foreach fid in array coalesce(added, '{}'::text[]) loop
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

  -- تعديل المالك: إشعار للمفوَّض الحالي بما تغيّر (آخر حدث في السجل).
  if tg_op = 'UPDATE' and actor = new.user_id then
    log_text := (
      select substr(t.p, position('|' in t.p) + 1)
      from unnest(new.permissions) with ordinality as t(p, n)
      where t.p like '@log:%' and not (t.p = any(old.permissions))
      order by t.n desc limit 1
    );
    if log_text is null and (
      (old.scope, old.start_date, old.end_date, old.is_paused)
        is distinct from (new.scope, new.start_date, new.end_date, new.is_paused)
      or array(
        select p from unnest(old.permissions) as p
        where p not like '@log:%' order by p
      ) is distinct from array(
        select p from unnest(new.permissions) as p
        where p not like '@log:%' order by p
      )
    ) then
      log_text := 'تعديل التفويض';
    end if;
    if log_text is not null then
      foreach fid in array new_ids loop
        continue when fid = any(coalesce(added, '{}'::text[]));
        rid := null;
        select id into rid from public.profiles where fnd_id = fid;
        if rid is not null and rid is distinct from actor then
          insert into public.fundly_inbox (
            recipient_id, sender_id, sender_name, sender_fnd,
            source, record_id, entry_type, title, action, note
          ) values (
            rid, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
            'delegations', new.id, 'تعديل تفويض', coalesce(new.scope, ''),
            'activity',
            jsonb_build_object('kind', 'delegation_change', 'what', log_text)::text
          );
        end if;
      end loop;
    end if;
  end if;
  return new;
end $$;

-- حذف المالك للتفويض: إشعار للمفوَّض.
create or replace function public.fundly_delegation_deleted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_name text;
  actor_fnd text;
  fid text;
  rid uuid;
begin
  if actor is null or actor <> old.user_id then
    return old;
  end if;
  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;
  foreach fid in array coalesce(old.shared_ids, '{}'::text[]) loop
    rid := null;
    select id into rid from public.profiles where fnd_id = fid;
    if rid is not null and rid <> actor then
      insert into public.fundly_inbox (
        recipient_id, sender_id, sender_name, sender_fnd,
        source, record_id, entry_type, title, action, note
      ) values (
        rid, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
        'delegations', old.id, 'حذف تفويض', coalesce(old.scope, ''),
        'activity',
        jsonb_build_object('kind', 'delegation_change', 'what', 'حذف التفويض')::text
      );
    end if;
  end loop;
  return old;
end $$;

drop trigger if exists fundly_delegation_deleted on public.delegations;
create trigger fundly_delegation_deleted
  after delete on public.delegations
  for each row execute function public.fundly_delegation_deleted();
