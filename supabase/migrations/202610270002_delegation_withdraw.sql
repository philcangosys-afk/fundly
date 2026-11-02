-- ============================================================
-- fundly — انسحاب المفوَّض من التفويض والعودة إليه
-- ============================================================
-- شغّله بعد 202610270001. آمن لإعادة التشغيل.
--
-- المفوَّض يستطيع «إلغاء التفويض» من عنده (@accept:withdrawn): يفقد
-- الوصول فورًا، ويصل للمالك إشعار «انسحب من التفويض». ويستطيع العودة
-- (@accept:accepted) ما دام المالك لم يُنهِ التفويض أو يحذفه.
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

-- الانسحاب إشعار للاطلاع (مثل الرفض) لا طلب جديد.
create or replace function public.fundly_inbox_action()
returns trigger
language plpgsql
as $$
begin
  if new.source = 'delegations' and new.action = 'invite' then
    new.action := case new.entry_type
      when 'قبول تفويض' then 'accepted'
      when 'رفض تفويض' then 'rejected'
      when 'انسحاب من تفويض' then 'rejected'
      else 'invite' end;
  end if;
  return new;
end $$;
