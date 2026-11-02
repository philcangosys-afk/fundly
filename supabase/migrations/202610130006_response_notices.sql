-- ============================================================
-- fundly — رد القبول أو الرفض يصل للمرسل
-- ============================================================
-- شغّله بعد 202610130005. آمن لإعادة التشغيل.
--
-- حين يقبل المستلم عهدة أو دَينًا أُسند إليه، أو يقبل دعوة رحلة أو
-- مشاركة (أو يرفضها)، يصل للمرسل طلب في صندوقه يظهر عند فتح التطبيق،
-- ويُضاف المستلم عنده إلى «الأفراد والجهات» باسمه ورقمه.
-- ============================================================

-- نوع الإشعار: invite (دعوة/إسناد جديد) أو accepted / rejected (رد).
alter table public.fundly_inbox
  add column if not exists action text not null default 'invite';

-- قراءة نص JSON داخل التفاصيل بلا خطأ إن كان تالفًا.
create or replace function public.fundly_try_jsonb(p_text text)
returns jsonb
language plpgsql
immutable
as $$
begin
  if p_text is null or btrim(p_text) = '' then
    return null;
  end if;
  return p_text::jsonb;
exception
  when others then
    return null;
end $$;

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
  old_state text;
  new_state text;
  response text;
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

  -- لا طلبات بلا مُرسِل (تحديث من لوحة Supabase مثلًا).
  if actor is null then
    return new;
  end if;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;

  -- ---------- رد الطرف الآخر على ما أُرسل إليه ----------
  if tg_op = 'UPDATE' and actor <> new.user_id then
    response := null;
    if tg_table_name = 'personal_entries' then
      -- العهدة والدَّين: حالة الإسناد.
      old_state := old.details ->> 'عهدة_حالة_الإسناد';
      new_state := new.details ->> 'عهدة_حالة_الإسناد';
      if new_state is distinct from old_state then
        response := case new_state
          when 'مقبولة' then 'accepted'
          when 'مرفوضة' then 'rejected'
          else null end;
      end if;
    elsif tg_table_name = 'shared_entries' and actor_fnd is not null then
      -- الرحلة والمشاركة: قبول الأعضاء {الرقم: {state}}.
      old_state := public.fundly_try_jsonb(old.details ->> 'قبول الأعضاء')
        -> actor_fnd ->> 'state';
      new_state := public.fundly_try_jsonb(new.details ->> 'قبول الأعضاء')
        -> actor_fnd ->> 'state';
      if new_state is distinct from old_state
         and new_state in ('accepted', 'rejected') then
        response := new_state;
      end if;
    end if;
    if response is not null then
      insert into public.fundly_inbox (
        recipient_id, sender_id, sender_name, sender_fnd,
        source, record_id, entry_type, title, action
      ) values (
        new.user_id, actor, coalesce(actor_name, ''), coalesce(actor_fnd, ''),
        tg_table_name, new.id, coalesce(new.entry_type, ''),
        coalesce(new.title, ''), response
      );
    end if;
  end if;

  -- ---------- رقم جديد أُضيف: يصله الطلب ----------
  if tg_op = 'UPDATE' then
    added := array(
      select x
      from unnest(new_ids) as x
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
        tg_table_name, new.id, coalesce(new.entry_type, ''),
        coalesce(new.title, '')
      );
    end if;
  end loop;

  return new;
end $$;

-- ردود التفويض أيضًا بنوع الإشعار نفسه.
update public.fundly_inbox set action = 'accepted'
where source = 'delegations' and entry_type = 'قبول تفويض' and action = 'invite';
update public.fundly_inbox set action = 'rejected'
where source = 'delegations' and entry_type = 'رفض تفويض' and action = 'invite';

create or replace function public.fundly_inbox_action()
returns trigger
language plpgsql
as $$
begin
  if new.source = 'delegations' and new.action = 'invite' then
    new.action := case new.entry_type
      when 'قبول تفويض' then 'accepted'
      when 'رفض تفويض' then 'rejected'
      else 'invite' end;
  end if;
  return new;
end $$;

drop trigger if exists fundly_inbox_action on public.fundly_inbox;
create trigger fundly_inbox_action
  before insert on public.fundly_inbox
  for each row execute function public.fundly_inbox_action();
