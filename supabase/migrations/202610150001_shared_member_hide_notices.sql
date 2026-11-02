-- ============================================================
-- fundly — الأرشفة والحذف في الالتزام المشترك لكل عضو وحده
-- ============================================================
-- شغّله بعد 202610130006. آمن لإعادة التشغيل.
--
-- حين يؤرشف عضو التزامًا مشتركًا أو يحذفه من عنده، يُضاف رقمه التعريفي
-- إلى «مؤرشف عند» أو «محذوف عند» داخل تفاصيل السجل، ويبقى السجل عند
-- بقية الأعضاء. هذا المشغّل يرسل لبقية الأعضاء (وللمالك) إشعارًا بذلك،
-- وكل واحد منهم يقرر: حذف عنده أو أرشفة عنده أو إبقاؤه.
--
-- action في fundly_inbox: archived (أرشفه عنده) / removed (حذفه من عنده).
-- لا يصل الإشعار لمن حذفه من عنده سابقًا، ولا إشعار الأرشفة لمن أرشفه.
-- ============================================================

create or replace function public.fundly_shared_hide_notices()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  actor_name text;
  actor_fnd text;
  list_key text;
  kind text;
  old_list jsonb;
  new_list jsonb;
  removed_list jsonb;
  rid uuid;
begin
  if actor is null then
    return new;
  end if;

  select display_name, fnd_id into actor_name, actor_fnd
  from public.profiles where id = actor;
  if coalesce(actor_fnd, '') = '' then
    return new;
  end if;

  removed_list := public.fundly_try_jsonb(new.details ->> 'محذوف عند');
  if removed_list is null or jsonb_typeof(removed_list) <> 'array' then
    removed_list := '[]'::jsonb;
  end if;

  foreach list_key in array array['محذوف عند', 'مؤرشف عند'] loop
    old_list := public.fundly_try_jsonb(old.details ->> list_key);
    if old_list is null or jsonb_typeof(old_list) <> 'array' then
      old_list := '[]'::jsonb;
    end if;
    new_list := public.fundly_try_jsonb(new.details ->> list_key);
    if new_list is null or jsonb_typeof(new_list) <> 'array' then
      new_list := '[]'::jsonb;
    end if;

    -- رقمي أُضيف الآن إلى القائمة (وليس موجودًا قبل).
    if (new_list ? actor_fnd) and not (old_list ? actor_fnd) then
      kind := case list_key when 'محذوف عند' then 'removed' else 'archived' end;
      for rid in
        select p.id
        from public.profiles p
        where (p.id = new.user_id
               or p.fnd_id = any(coalesce(new.shared_ids, '{}'::text[])))
          and p.id <> actor
          and not (removed_list ? coalesce(p.fnd_id, ''))
          and not (kind = 'archived' and new_list ? coalesce(p.fnd_id, ''))
      loop
        insert into public.fundly_inbox (
          recipient_id, sender_id, sender_name, sender_fnd,
          source, record_id, entry_type, title, action
        ) values (
          rid, actor, coalesce(actor_name, ''), actor_fnd,
          tg_table_name, new.id, coalesce(new.entry_type, ''),
          coalesce(new.title, ''), kind
        );
      end loop;
    end if;
  end loop;

  return new;
end $$;

drop trigger if exists fundly_shared_hide_notices on public.shared_entries;
create trigger fundly_shared_hide_notices
  after update on public.shared_entries
  for each row execute function public.fundly_shared_hide_notices();
